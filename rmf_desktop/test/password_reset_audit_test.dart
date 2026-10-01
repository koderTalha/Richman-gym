import 'package:bcrypt/bcrypt.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/logs/logs_screen.dart';

/// "Forgot password?" accepts the password the app ships with, which is in
/// this public repository. The owner chose to keep that way back in (audit
/// SEC-001) rather than risk locking themselves out for good, on one
/// condition: nobody can use it without leaving a mark the owner can see.
///
/// So these tests do not ask for the reset to be refused — they pin down that
/// every attempt, refused or not, lands in the audit log, shows on the Logs
/// screen, and carries neither password with it.
void main() {
  late AppDatabase db;
  late SettingsRepository repo;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    // The owner has long since replaced the shipped password with their own.
    await seedDatabase(db, adminPassword: 'OwnersOwnSecret9');
    repo = SettingsRepository(db);
  });

  tearDown(() => db.close());

  Future<List<AuditEvent>> events() => db.select(db.auditEvents).get();

  /// Everything a row puts on screen, in one string.
  String shown(AuditEvent e) =>
      [e.summary, e.detail, e.actorName, e.memberName].join('\n');

  void expectNoSecrets(AuditEvent e, List<String> secrets) {
    for (final secret in secrets) {
      expect(shown(e), isNot(contains(secret)),
          reason: 'the audit log is on screen for anyone signed in; a '
              'password typed into the form must never be copied into it');
    }
  }

  test('a reset with the public default password still works, and is audited',
      () async {
    final problem = await repo.resetPassword(
      email: defaultAdminEmail,
      defaultPassword: defaultAdminPassword,
      newPassword: 'StaffChoseThis1',
    );

    // Kept on purpose: the owner's own way back in.
    expect(problem, isNull);
    final hash = (await db.select(db.users).getSingle()).passwordHash;
    expect(BCrypt.checkpw('StaffChoseThis1', hash), isTrue);

    final logged = await events();
    expect(logged, hasLength(1),
        reason: 'the owner must be able to see on the Logs screen that their '
            'password was reset, and when');
    final event = logged.single;
    expect(event.action, AuditAction.accountPasswordReset);
    expect(event.outcome, AuditOutcome.success);
    expect(event.summary, contains('password reset'));
    expect(event.detail, contains(defaultAdminEmail));
    expectNoSecrets(
        event, ['StaffChoseThis1', defaultAdminPassword, 'OwnersOwnSecret9']);
  });

  test('a wrong default password is refused and audited', () async {
    final problem = await repo.resetPassword(
      email: defaultAdminEmail,
      // Somebody tries the owner's real password, or a guess at it.
      defaultPassword: 'GuessedAtIt77',
      newPassword: 'StaffChoseThis1',
    );

    expect(problem, 'The default password is incorrect.');
    final event = (await events()).single;
    expect(event.action, AuditAction.accountPasswordResetRefused);
    expect(event.outcome, AuditOutcome.refused);
    expect(event.summary, contains('default password was wrong'));
    expectNoSecrets(event, ['GuessedAtIt77', 'StaffChoseThis1']);
  });

  test('an unknown email is refused and audited, with what was typed',
      () async {
    final problem = await repo.resetPassword(
      email: '  Someone@Elsewhere.example ',
      defaultPassword: defaultAdminPassword,
      newPassword: 'StaffChoseThis1',
    );

    expect(problem, 'No account uses that email.');
    final event = (await events()).single;
    expect(event.outcome, AuditOutcome.refused);
    expect(event.detail, contains('someone@elsewhere.example'));
    expectNoSecrets(event, ['StaffChoseThis1', defaultAdminPassword]);
  });

  test('an unusable new password is refused and audited', () async {
    for (final next in ['short', defaultAdminPassword]) {
      final problem = await repo.resetPassword(
        email: defaultAdminEmail,
        defaultPassword: defaultAdminPassword,
        newPassword: next,
      );
      expect(problem, isNotNull);
    }

    final logged = await events();
    expect(logged, hasLength(2));
    for (final event in logged) {
      expect(event.action, AuditAction.accountPasswordResetRefused);
      expect(event.outcome, AuditOutcome.refused);
      expectNoSecrets(event, ['short', defaultAdminPassword]);
    }
  });

  test('a stranger typing a page of text into the email gets one short line',
      () async {
    await repo.resetPassword(
      email: 'x' * 5000,
      defaultPassword: 'wrong',
      newPassword: 'StaffChoseThis1',
    );

    expect((await events()).single.detail!.length, lessThan(400));
  });

  testWidgets('every attempt is on the Logs screen, refusals under Problems too',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(1400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    // Bcrypt and the database run outside the fake clock.
    await tester.runAsync(() async {
      await repo.resetPassword(
        email: defaultAdminEmail,
        defaultPassword: 'wrong guess',
        newPassword: 'StaffChoseThis1',
      );
      await repo.resetPassword(
        email: defaultAdminEmail,
        defaultPassword: defaultAdminPassword,
        newPassword: 'StaffChoseThis1',
      );
    });

    await tester.pumpWidget(
      RepositoryProvider<AuditRepository>(
        create: (_) => AuditRepository(db),
        child: MaterialApp(
          theme: buildDarkTheme(),
          home: const Scaffold(body: LogsScreen()),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }

    expect(find.text('Admin password reset with the default password'),
        findsOneWidget);
    expect(find.text('Password reset refused: the default password was wrong'),
        findsOneWidget);
    expect(find.textContaining('Password reset refused'), findsWidgets);
    expect(find.textContaining('StaffChoseThis1'), findsNothing);

    await tester.tap(find.text('Problems'));
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }

    expect(find.text('Password reset refused: the default password was wrong'),
        findsOneWidget,
        reason: 'a run of refused resets is somebody trying their luck, and '
            'belongs with everything else that went wrong');
    expect(find.text('Admin password reset with the default password'),
        findsNothing);
  });
}
