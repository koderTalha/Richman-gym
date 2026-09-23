import 'package:bcrypt/bcrypt.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/auth_bloc.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/login_screen.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // An owner who has long since replaced the shipped password and forgotten
    // the one they chose.
    await seedDatabase(db, adminPassword: 'ForgottenPass1');
    repo = SettingsRepository(db);
  });

  tearDown(() => db.close());

  Future<String> currentHash() async =>
      (await db.select(db.users).getSingle()).passwordHash;

  group('resetPassword', () {
    test('sets a new password when the default password is given', () async {
      final error = await repo.resetPassword(
        email: defaultAdminEmail,
        defaultPassword: defaultAdminPassword,
        newPassword: 'BrandNewPass2',
      );

      expect(error, isNull);
      expect(BCrypt.checkpw('BrandNewPass2', await currentHash()), isTrue);
      expect(BCrypt.checkpw('ForgottenPass1', await currentHash()), isFalse);
    });

    test('matches the email however it was typed', () async {
      final error = await repo.resetPassword(
        email: '  Admin@RichManFitness.local ',
        defaultPassword: defaultAdminPassword,
        newPassword: 'BrandNewPass2',
      );

      expect(error, isNull);
    });

    test('refuses a wrong default password and leaves the hash alone',
        () async {
      final before = await currentHash();

      final error = await repo.resetPassword(
        email: defaultAdminEmail,
        defaultPassword: 'ForgottenPass1',
        newPassword: 'BrandNewPass2',
      );

      expect(error, 'The default password is incorrect.');
      expect(await currentHash(), before);
    });

    test('gives the same answer for an unknown email as a wrong password',
        () async {
      final error = await repo.resetPassword(
        email: 'nobody@example.com',
        defaultPassword: 'wrong',
        newPassword: 'BrandNewPass2',
      );

      expect(error, 'The default password is incorrect.');
    });

    test('names an unknown email once the default password is right',
        () async {
      final error = await repo.resetPassword(
        email: 'nobody@example.com',
        defaultPassword: defaultAdminPassword,
        newPassword: 'BrandNewPass2',
      );

      expect(error, 'No account uses that email.');
    });

    test('refuses a new password shorter than 8 characters', () async {
      final before = await currentHash();

      final error = await repo.resetPassword(
        email: defaultAdminEmail,
        defaultPassword: defaultAdminPassword,
        newPassword: 'short',
      );

      expect(error, contains('at least 8'));
      expect(await currentHash(), before);
    });

    test('refuses the default password as the new one', () async {
      final before = await currentHash();

      final error = await repo.resetPassword(
        email: defaultAdminEmail,
        defaultPassword: defaultAdminPassword,
        newPassword: defaultAdminPassword,
      );

      expect(error, contains('installed with'));
      expect(await currentHash(), before);
    });
  });

  group('reset screen', () {
    Future<void> pumpLogin(WidgetTester tester) async {
      await tester.pumpWidget(
        RepositoryProvider.value(
          value: repo,
          child: MaterialApp(
            theme: buildDarkTheme(),
            home: BlocProvider(
              create: (_) => AuthBloc(db),
              child: const LoginScreen(),
            ),
          ),
        ),
      );
    }

    Future<void> fill(
      WidgetTester tester, {
      required String defaultPassword,
      String next = 'BrandNewPass2',
      String? confirm,
    }) async {
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Default password'),
          defaultPassword);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'New password'), next);
      await tester.enterText(
          find.widgetWithText(TextFormField, 'Confirm new password'),
          confirm ?? next);
    }

    // Bcrypt runs outside the fake clock, so each save needs real time.
    Future<void> save(WidgetTester tester) async {
      await tester.tap(find.text('Reset password'));
      for (var i = 0; i < 20; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pump();
      }
      await tester.pumpAndSettle();
    }

    testWidgets('is reachable from the login screen', (tester) async {
      await pumpLogin(tester);

      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(TextFormField, 'Default password'),
          findsOneWidget);
    });

    testWidgets('a correct default password resets and returns to sign in',
        (tester) async {
      await pumpLogin(tester);
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      await fill(tester, defaultPassword: defaultAdminPassword);
      await save(tester);

      expect(find.text('Admin sign in'), findsOneWidget);
      expect(find.textContaining('Password reset'), findsOneWidget);
      final hash = await tester.runAsync(currentHash);
      expect(BCrypt.checkpw('BrandNewPass2', hash!), isTrue);
    });

    testWidgets('a wrong default password stays on the screen with a reason',
        (tester) async {
      await pumpLogin(tester);
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      await fill(tester, defaultPassword: 'guess');
      await save(tester);

      expect(find.text('The default password is incorrect.'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Default password'),
          findsOneWidget);
    });

    testWidgets('mismatched new passwords are caught before saving',
        (tester) async {
      await pumpLogin(tester);
      await tester.tap(find.text('Forgot password?'));
      await tester.pumpAndSettle();

      await fill(tester,
          defaultPassword: defaultAdminPassword, confirm: 'Different99');
      await tester.tap(find.text('Reset password'));
      await tester.pumpAndSettle();

      expect(find.text('The two passwords do not match'), findsOneWidget);
    });
  });
}
