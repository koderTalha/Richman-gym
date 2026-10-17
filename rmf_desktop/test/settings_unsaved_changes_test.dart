import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/auth_bloc.dart';
import 'package:rich_man_fitness/bloc/branding_cubit.dart';
import 'package:rich_man_fitness/bloc/theme_cubit.dart';
import 'package:rich_man_fitness/bloc/update_bloc.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/payment_repository.dart';
import 'package:rich_man_fitness/data/receipt_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';
import 'package:rich_man_fitness/domain/app_version.dart';
import 'package:rich_man_fitness/services/update/update_service.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/theme/branding_config.dart';
import 'package:rich_man_fitness/ui/app_shell.dart';

import 'support/still_motion.dart';

/// Settings no longer has a save button per section. Edits raise one bar —
/// "You have unsaved changes" — that saves or discards everything, and the
/// owner is asked before leaving the screen with edits still pending.
void main() {
  late AppDatabase db;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
  });

  tearDown(() async => db.close());

  Future<void> pumpSettings(WidgetTester tester) async {
    // Wide enough for the sidebar and the two-up fields without overflow.
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final admin = await db.select(db.users).getSingle();
    final audit = AuditRepository(db);

    await tester.pumpWidget(MultiRepositoryProvider(
      providers: [
        RepositoryProvider<AppDatabase>.value(value: db),
        RepositoryProvider<MemberRepository>(
            create: (_) => MemberRepository(db)),
        RepositoryProvider<PaymentRepository>(
            create: (_) => PaymentRepository(db)),
        RepositoryProvider<ReceiptRepository>(
            create: (_) => ReceiptRepository(db)),
        RepositoryProvider<SettingsRepository>(
            create: (_) => SettingsRepository(db, audit: audit)),
      ],
      child: MultiBlocProvider(
        providers: [
          BlocProvider<AuthBloc>(
              create: (_) => AuthBloc(db, restored: admin)),
          BlocProvider<ThemeCubit>(
              create: (_) => ThemeCubit(SettingsRepository(db))),
          BlocProvider<BrandingCubit>(
            create: (_) => BrandingCubit(SettingsRepository(db),
                initial: const BrandingConfig()),
          ),
          BlocProvider<UpdateBloc>(
            create: (_) => UpdateBloc(UpdateService(
              db: db,
              currentVersion: AppVersion.unknown,
              audit: audit,
            )),
          ),
        ],
        child: MaterialApp(
          theme: buildDarkTheme(),
          builder: stillMotion,
          home: const AppShell(),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // The sidebar entry; the page title does not exist yet.
    await tester.tap(find.text('Settings'));
    await tester.pumpAndSettle();
  }

  Finder gymName() => find.widgetWithText(TextField, 'Gym name');

  /// The bar is always in the tree so it can animate; what matters is whether
  /// it is showing.
  bool barShowing(WidgetTester tester) {
    final opacity = tester.widget<AnimatedOpacity>(find.ancestor(
      of: find.textContaining('You have unsaved changes'),
      matching: find.byType(AnimatedOpacity),
    ).first);
    return opacity.opacity == 1;
  }

  /// Lets a snackbar run out so no timer is left pending at the end.
  Future<void> drain(WidgetTester tester) =>
      tester.pump(const Duration(seconds: 5));

  testWidgets('no bar until something is edited', (tester) async {
    await pumpSettings(tester);

    expect(barShowing(tester), isFalse);
    expect(find.text('Save gym details'), findsNothing,
        reason: 'the per-section save button is gone');
  });

  testWidgets('editing a field raises the bar, and undoing it lowers it',
      (tester) async {
    await pumpSettings(tester);
    final original =
        tester.widget<TextField>(gymName()).controller!.text;

    await tester.enterText(gymName(), 'Rich Man Fitness DHA');
    await tester.pumpAndSettle();
    expect(barShowing(tester), isTrue);

    // Typed back to what is stored: nothing to save, so nothing to nag about.
    await tester.enterText(gymName(), original);
    await tester.pumpAndSettle();
    expect(barShowing(tester), isFalse);
  });

  testWidgets('a trailing space is not a change', (tester) async {
    await pumpSettings(tester);
    final original =
        tester.widget<TextField>(gymName()).controller!.text;

    await tester.enterText(gymName(), '$original ');
    await tester.pumpAndSettle();

    expect(barShowing(tester), isFalse,
        reason: 'it would save as exactly what is stored');
  });

  testWidgets('Discard puts the field back and lowers the bar',
      (tester) async {
    await pumpSettings(tester);
    final original =
        tester.widget<TextField>(gymName()).controller!.text;

    await tester.enterText(gymName(), 'Somewhere Else');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard'));
    await tester.pumpAndSettle();

    expect(tester.widget<TextField>(gymName()).controller!.text, original);
    expect(barShowing(tester), isFalse);
    expect((await SettingsRepository(db).get()).gymName, original,
        reason: 'nothing was written');
  });

  testWidgets('Save changes writes the edit and lowers the bar',
      (tester) async {
    await pumpSettings(tester);

    await tester.enterText(gymName(), 'Rich Man Fitness DHA');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save changes'));
    await tester.pumpAndSettle();

    expect((await SettingsRepository(db).get()).gymName,
        'Rich Man Fitness DHA');
    expect(barShowing(tester), isFalse,
        reason: 'what is on screen is now what is stored');
    await drain(tester);
  });

  testWidgets('a form that cannot be saved greys out Save, not the bar',
      (tester) async {
    await pumpSettings(tester);

    await tester.enterText(gymName(), '');
    await tester.pumpAndSettle();

    expect(barShowing(tester), isTrue,
        reason: 'the owner still needs to know something is unsaved');
    final save = tester.widget<OutlinedButton>(
        find.widgetWithText(OutlinedButton, 'Save changes'));
    expect(save.onPressed, isNull, reason: 'a receipt needs a gym name');
  });

  testWidgets('an edit survives a look at another tab', (tester) async {
    await pumpSettings(tester);

    await tester.enterText(gymName(), 'Rich Man Fitness DHA');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();
    expect(barShowing(tester), isTrue,
        reason: 'the gym tab is out of sight, not thrown away');

    await tester.tap(find.text('Gym details'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(gymName()).controller!.text,
        'Rich Man Fitness DHA');
  });

  testWidgets('leaving with unsaved edits asks first', (tester) async {
    await pumpSettings(tester);

    await tester.enterText(gymName(), 'Rich Man Fitness DHA');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Members'));
    await tester.pumpAndSettle();
    expect(find.text('Discard unsaved changes?'), findsOneWidget);

    // Keep editing: still on Settings, edit intact.
    await tester.tap(find.text('Keep editing'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(gymName()).controller!.text,
        'Rich Man Fitness DHA');

    // Ask again and agree to lose it.
    await tester.tap(find.text('Members'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Discard changes'));
    await tester.pumpAndSettle();

    expect(gymName(), findsNothing, reason: 'Settings has been left');
    expect((await SettingsRepository(db).get()).gymName,
        isNot('Rich Man Fitness DHA'));
  });

  testWidgets('the prefix field previews the next receipt number as typed',
      (tester) async {
    await pumpSettings(tester);
    final year = DateTime.now().year;

    // A fresh database has issued nothing, so the next receipt is the first.
    expect(find.text('Next receipt: RMF-$year-000001'), findsOneWidget);

    await tester.enterText(
        find.widgetWithText(TextField, 'Receipt prefix'), 'gym');
    await tester.pumpAndSettle();
    expect(find.text('Next receipt: GYM-$year-000001'), findsOneWidget,
        reason: 'shown exactly as the receipt will print it');
  });

  testWidgets('password rules tick off as typed and gate the button',
      (tester) async {
    await pumpSettings(tester);
    await tester.tap(find.text('Account'));
    await tester.pumpAndSettle();

    VoidCallback? changeButton() => tester
        .widget<OutlinedButton>(
            find.widgetWithText(OutlinedButton, 'Change password'))
        .onPressed;
    bool ticked(String rule) => tester
        .widget<Icon>(find.descendant(
          of: find.ancestor(of: find.text(rule), matching: find.byType(Row)),
          matching: find.byType(Icon),
        ).first)
        .icon == Icons.check;

    expect(ticked('At least 8 characters'), isFalse);
    expect(ticked('Passwords match'), isFalse);
    expect(changeButton(), isNull);

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Current password'), 'admin123');
    await tester.enterText(
        find.widgetWithText(TextFormField, 'New password'), 'stronger1');
    await tester.pumpAndSettle();
    expect(ticked('At least 8 characters'), isTrue);
    expect(ticked('Passwords match'), isFalse);
    expect(changeButton(), isNull, reason: 'not confirmed yet');

    await tester.enterText(
        find.widgetWithText(TextFormField, 'Confirm new password'),
        'stronger1');
    await tester.pumpAndSettle();
    expect(ticked('Passwords match'), isTrue);
    expect(changeButton(), isNotNull);
  });

  testWidgets('leaving with nothing unsaved does not ask', (tester) async {
    await pumpSettings(tester);

    await tester.tap(find.text('Members'));
    await tester.pumpAndSettle();

    expect(find.text('Discard unsaved changes?'), findsNothing);
    expect(gymName(), findsNothing);
  });
}
