import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/branding_cubit.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';
import 'package:rich_man_fitness/theme/app_theme.dart';
import 'package:rich_man_fitness/theme/branding_config.dart';
import 'package:rich_man_fitness/theme/theme_preset.dart';
import 'package:rich_man_fitness/ui/appearance/appearance_screen.dart';

/// The Appearance screen as the owner drives it: pick, preview, apply, cancel.
void main() {
  late AppDatabase db;
  late SettingsRepository settings;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsRepository(db);
    await db.into(db.gymSettings).insert(
        const GymSettingsCompanion(id: Value(1)),
        mode: InsertMode.insertOrIgnore);
  });

  tearDown(() => db.close());

  /// Pumps the screen inside a MaterialApp whose theme follows the cubit, the
  /// same way main.dart wires it — otherwise "preview repaints the app" could
  /// not be observed at all.
  Future<BrandingCubit> pumpScreen(WidgetTester tester) async {
    final branding = await settings.branding();
    final cubit = BrandingCubit(settings, initial: branding);

    await tester.pumpWidget(BlocProvider<BrandingCubit>.value(
      value: cubit,
      child: BlocBuilder<BrandingCubit, BrandingState>(
        builder: (context, state) => MaterialApp(
          theme: buildDarkThemeFor(state.draft),
          home: const Scaffold(body: AppearanceScreen()),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    return cubit;
  }

  testWidgets('shows a card for every preset', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpScreen(tester);

    for (final preset in ThemePreset.all) {
      expect(find.text(preset.name), findsOneWidget,
          reason: '${preset.name} must be offered');
    }
  });

  testWidgets('marks the saved theme as currently applied', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpScreen(tester);

    expect(find.text('Currently applied'), findsOneWidget,
        reason: 'exactly one theme is active at a time');
  });

  testWidgets('picking a theme previews it without saving', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final cubit = await pumpScreen(tester);

    await tester.tap(find.text('Ocean Teal'));
    await tester.pumpAndSettle();

    expect(cubit.state.draft.presetId, 'oceanTeal');
    expect(find.text('Previewing — not saved yet'), findsOneWidget);
    expect((await settings.branding()).presetId, ThemePreset.fallback.id,
        reason: 'nothing reaches the database until Apply');
  });

  testWidgets('the preview actually repaints the app', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpScreen(tester);

    MaterialApp app() =>
        tester.widget<MaterialApp>(find.byType(MaterialApp));
    final before = app().theme!.extension<AppPalette>()!.accent;

    await tester.tap(find.text('Royal Purple'));
    await tester.pumpAndSettle();

    final after = app().theme!.extension<AppPalette>()!.accent;
    expect(after, isNot(before));
    expect(after, ThemePreset.royalPurple.primary,
        reason: 'the owner should see their real screens in the new brand');
  });

  testWidgets('Cancel puts the saved theme back', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final cubit = await pumpScreen(tester);

    await tester.tap(find.text('Black & Gold'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(cubit.state.draft.presetId, ThemePreset.fallback.id);
    expect(find.text('Previewing — not saved yet'), findsNothing);
  });

  testWidgets('Apply saves the theme and dismisses the bar', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final cubit = await pumpScreen(tester);

    await tester.tap(find.text('Power Orange'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();

    expect(cubit.state.isPreviewing, isFalse);
    expect((await settings.branding()).presetId, 'powerOrange',
        reason: 'Apply is what persists');
  });

  testWidgets('offers the three receipt styles', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpScreen(tester);

    expect(find.text('Classic'), findsOneWidget);
    expect(find.text('Modern'), findsOneWidget);
    expect(find.text('Minimal'), findsOneWidget);
  });

  testWidgets('shows the empty state when no logo is set', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpScreen(tester);

    expect(find.text('No logo set'), findsOneWidget);
    expect(find.text('No logo'), findsOneWidget,
        reason: 'the preview frame says so rather than showing a broken image');
  });

  testWidgets('says SVG is not supported, where the owner will read it',
      (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpScreen(tester);

    expect(
      find.textContaining('SVG files are not supported'),
      findsOneWidget,
      reason: 'the refusal should not be a surprise after choosing a file',
    );
  });

  testWidgets('warns when custom colours would be unreadable', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final cubit = await pumpScreen(tester);

    // Near-white text on a near-white background: the case the app cannot fix
    // automatically, because the owner has set both ends of the pair.
    cubit.preview(const BrandingConfig(
      presetId: BrandingConfig.customId,
      custom: CustomColors(
        background: Color(0xFFF7F7F8),
        textPrimary: Color(0xFFFFFFFF),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.textContaining('below the'), findsOneWidget);
  });

  testWidgets('confirms when custom colours are readable', (tester) async {
    tester.view.physicalSize = const Size(1600, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await pumpScreen(tester);

    expect(find.textContaining('comfortably'), findsOneWidget);
  });
}
