import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/auth_bloc.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/data/session_repository.dart';
import 'package:rich_man_fitness/domain/inactivity.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/ui/idle_lock.dart';
import 'package:rich_man_fitness/ui/login_screen.dart';

const _password = 'owners-own-password';

/// Stands in for the shell: a screen, a pushed member page and a dialog on
/// top of it, which is where the owner is most of the time.
class _Desk extends StatelessWidget {
  const _Desk({required this.onConfirm});

  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(children: [
        const Text('Desk'),
        TextButton(
          onPressed: () => Navigator.of(context).push(MaterialPageRoute(
            builder: (context) => Scaffold(
              body: Column(children: [
                const Text('Member details'),
                TextButton(
                  onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => AlertDialog(
                      content: const Text('Confirm payment'),
                      actions: [
                        // Focused, so Enter would press it.
                        TextButton(
                            autofocus: true,
                            onPressed: onConfirm,
                            child: const Text('Confirm')),
                      ],
                    ),
                  ),
                  child: const Text('Record payment'),
                ),
              ]),
            ),
          )),
          child: const Text('Open member'),
        ),
        TextButton(onPressed: onConfirm, child: const Text('Delete member')),
      ]),
    );
  }
}

/// The inactivity lock as main.dart wires it: the app keyed on who is signed
/// in, [IdleLock] above the Navigator. Driven by a clock the test moves, with
/// timers advanced alongside it — except where a test deliberately moves only
/// the clock, which is what a sleeping computer looks like.
void main() {
  late AppDatabase db;
  late User admin;
  late DateTime now;
  late int confirmed;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db, adminPassword: _password);
    admin = await db.select(db.users).getSingle();
    now = DateTime(2026, 10, 27, 9);
    confirmed = 0;
  });

  tearDown(() async => db.close());

  Future<AuthBloc> pumpApp(WidgetTester tester,
      {bool signedIn = true, DateTime? restoredActiveAt}) async {
    final sessions = SessionRepository(db);
    if (signedIn) await sessions.remember(admin.id, at: now);
    final bloc = AuthBloc(db,
        sessions: sessions,
        restored: signedIn ? admin : null,
        restoredActiveAt: restoredActiveAt);
    addTearDown(bloc.close);

    await tester.pumpWidget(BlocProvider.value(
      value: bloc,
      child: BlocBuilder<AuthBloc, AuthState>(
        buildWhen: (a, b) => a.user?.id != b.user?.id,
        builder: (context, auth) => MaterialApp(
          key: ValueKey(auth.user?.id),
          theme: buildDarkTheme(),
          builder: (context, child) =>
              IdleLock(clock: () => now, child: child!),
          home: BlocBuilder<AuthBloc, AuthState>(
            builder: (context, state) => state.user != null
                ? _Desk(onConfirm: () => confirmed++)
                : const LoginScreen(),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return bloc;
  }

  /// Time passes with the computer awake.
  Future<void> wait(WidgetTester tester, Duration d) async {
    now = now.add(d);
    await tester.pump(d);
    await tester.pumpAndSettle();
  }

  bool locked(WidgetTester tester) =>
      find.byType(LoginScreen).evaluate().isNotEmpty;

  final notice = find.textContaining('locked after 2 minutes of inactivity');

  testWidgets('120 seconds untouched locks the app and says why',
      (tester) async {
    await pumpApp(tester);

    await wait(tester, const Duration(seconds: 118));
    expect(find.text('Desk'), findsOneWidget);

    await wait(tester, const Duration(seconds: 3));
    expect(locked(tester), isTrue);
    expect(notice, findsOneWidget);
    expect(
        find.text('Your session was locked after 2 minutes of inactivity. '
            'Please log in again to continue.'),
        findsOneWidget);
  });

  testWidgets('a click moves the deadline on', (tester) async {
    await pumpApp(tester);

    await wait(tester, const Duration(seconds: 100));
    await tester.tap(find.text('Desk'));
    await wait(tester, const Duration(seconds: 100));

    expect(locked(tester), isFalse);

    await wait(tester, const Duration(seconds: 21));
    expect(locked(tester), isTrue);
  });

  testWidgets('an owner who keeps working is never interrupted',
      (tester) async {
    await pumpApp(tester);

    for (var i = 0; i < 20; i++) {
      await wait(tester, const Duration(seconds: 90));
      await tester.tap(find.text('Desk'));
    }

    expect(locked(tester), isFalse);
  });

  testWidgets('a key press counts, for keyboard-only use', (tester) async {
    await pumpApp(tester);

    await wait(tester, const Duration(seconds: 100));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await wait(tester, const Duration(seconds: 100));

    expect(locked(tester), isFalse);
  });

  testWidgets('the scroll wheel counts', (tester) async {
    await pumpApp(tester);

    await wait(tester, const Duration(seconds: 100));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(
        pointer.hover(tester.getCenter(find.text('Desk'))));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, 40)));
    await wait(tester, const Duration(seconds: 100));

    expect(locked(tester), isFalse);
  });

  testWidgets('the mouse drifting over the window does not count',
      (tester) async {
    await pumpApp(tester);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: Offset.zero);

    for (var i = 0; i < 12; i++) {
      await mouse.moveTo(Offset(10.0 * i, 10.0 * i));
      await wait(tester, const Duration(seconds: 10));
    }

    expect(locked(tester), isTrue);
  });

  testWidgets('background database work does not hold the lock off',
      (tester) async {
    await pumpApp(tester);

    // What reminders, the billing roll and the update check look like from
    // here: writes and rebuilds, but no input.
    for (var i = 0; i < 12; i++) {
      await tester.runAsync(() => (db.update(db.gymSettings)
            ..where((s) => s.id.equals(1)))
          .write(GymSettingsCompanion(gymName: Value('Gym $i'))));
      await wait(tester, const Duration(seconds: 10));
    }

    expect(locked(tester), isTrue);
  });

  testWidgets('a lock clears pushed screens and dialogs, and Back cannot '
      'return to them', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Open member'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record payment'));
    await tester.pumpAndSettle();
    expect(find.text('Confirm payment'), findsOneWidget);

    await wait(tester, inactivityLockAfter);

    expect(locked(tester), isTrue);
    expect(find.text('Confirm payment'), findsNothing);
    expect(find.text('Member details'), findsNothing);
    expect(Navigator.of(tester.element(find.byType(LoginScreen))).canPop(),
        isFalse);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(locked(tester), isTrue);
    expect(find.text('Member details'), findsNothing);
  });

  // The laptop lid closed for an hour: no timer ran, so the first click is
  // the first thing to notice. It must lock, and the button under it must not
  // act on the way out.
  testWidgets('the first click after sleep locks without pressing anything',
      (tester) async {
    await pumpApp(tester);

    now = now.add(const Duration(hours: 1));
    await tester.tap(find.text('Delete member'));
    await tester.pumpAndSettle();

    expect(confirmed, 0);
    expect(locked(tester), isTrue);
  });

  testWidgets('a late Enter does not confirm a dialog', (tester) async {
    await pumpApp(tester);
    await tester.tap(find.text('Open member'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Record payment'));
    await tester.pumpAndSettle();

    now = now.add(const Duration(hours: 1));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();

    expect(confirmed, 0);
    expect(locked(tester), isTrue);
  });

  testWidgets('bringing the window back after sleep locks straight away',
      (tester) async {
    await pumpApp(tester);

    now = now.add(const Duration(minutes: 10));
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(locked(tester), isTrue);
  });

  testWidgets('a restart keeps the deadline it had', (tester) async {
    await pumpApp(tester,
        restoredActiveAt: now.subtract(const Duration(seconds: 100)));

    await wait(tester, const Duration(seconds: 21));
    expect(locked(tester), isTrue);
  });

  testWidgets('the login form is never interrupted', (tester) async {
    await pumpApp(tester, signedIn: false);
    await tester.enterText(find.byType(TextFormField).last, 'half-typ');

    await wait(tester, const Duration(minutes: 10));

    expect(find.text('half-typ'), findsOneWidget);
    expect(notice, findsNothing);
  });

  testWidgets('signing in again starts a fresh two minutes', (tester) async {
    await pumpApp(tester);
    await wait(tester, inactivityLockAfter);
    expect(locked(tester), isTrue);

    await tester.enterText(find.byType(TextFormField).last, _password);
    await tester.tap(find.text('Sign in'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pumpAndSettle();
    expect(find.text('Desk'), findsOneWidget);

    await wait(tester, const Duration(seconds: 110));
    expect(locked(tester), isFalse);

    await wait(tester, const Duration(seconds: 11));
    expect(locked(tester), isTrue);
  });

  testWidgets('activity is written to the session for the next restart',
      (tester) async {
    await pumpApp(tester);

    await wait(tester, const Duration(seconds: 60));
    await tester.tap(find.text('Desk'));
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await tester.pump();

    final row = await tester
        .runAsync(() => db.select(db.appSessions).getSingle());
    expect(row!.lastActiveAt, now);
  });
}
