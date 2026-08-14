import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/auth_bloc.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/login_screen.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });

  tearDown(() async => db.close());

  Future<void> pumpLogin(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildDarkTheme(),
        home: BlocProvider(
          create: (_) => AuthBloc(db),
          child: const LoginScreen(),
        ),
      ),
    );
  }

  /// The password field is the only obscured one on the screen.
  bool isObscured(WidgetTester tester) {
    final fields = tester.widgetList<EditableText>(find.byType(EditableText));
    return fields.any((f) => f.obscureText);
  }

  testWidgets('the password is hidden when the screen opens', (tester) async {
    await pumpLogin(tester);

    expect(isObscured(tester), isTrue);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
    expect(find.byIcon(Icons.visibility_off_outlined), findsNothing);
  });

  testWidgets('tapping the eye reveals the password and swaps the icon',
      (tester) async {
    await pumpLogin(tester);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    expect(isObscured(tester), isFalse);
    expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
    expect(find.byIcon(Icons.visibility_outlined), findsNothing);
  });

  testWidgets('tapping again hides it', (tester) async {
    await pumpLogin(tester);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.visibility_off_outlined));
    await tester.pumpAndSettle();

    expect(isObscured(tester), isTrue);
    expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
  });

  testWidgets('revealing does not disturb what has been typed', (tester) async {
    await pumpLogin(tester);

    final field = find.byType(TextFormField).last;
    await tester.enterText(field, 'sup3r-s3cret');
    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();

    expect(find.text('sup3r-s3cret'), findsOneWidget);
  });

  testWidgets('the toggle is skipped when tabbing between fields',
      (tester) async {
    await pumpLogin(tester);

    final button = tester.widget<IconButton>(find.byType(IconButton));
    expect(button.focusNode?.skipTraversal, isTrue);
  });

  testWidgets('the toggle explains itself for screen readers', (tester) async {
    await pumpLogin(tester);
    expect(find.byTooltip('Show password'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.visibility_outlined));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Hide password'), findsOneWidget);
  });
}
