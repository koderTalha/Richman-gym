import 'package:drift/native.dart';
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/theme_cubit.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';

void main() {
  late AppDatabase db;
  late SettingsRepository settings;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    settings = SettingsRepository(db);
  });

  tearDown(() async => db.close());

  test('a fresh install opens dark, as the gym has always had it', () async {
    expect((await settings.get()).themeMode, 'dark');
    expect(ThemeCubit.parse((await settings.get()).themeMode), ThemeMode.dark);
  });

  test('toggling writes the choice to the database', () async {
    final cubit = ThemeCubit(settings);

    await cubit.toggle();

    expect(cubit.state, ThemeMode.light);
    expect((await settings.get()).themeMode, 'light');
  });

  test('the choice survives a restart', () async {
    await ThemeCubit(settings).toggle();

    // What main() does on the next launch.
    final reopened = ThemeCubit.parse((await settings.get()).themeMode);

    expect(reopened, ThemeMode.light);
  });

  test('toggling twice returns to dark and persists that too', () async {
    final cubit = ThemeCubit(settings);

    await cubit.toggle();
    await cubit.toggle();

    expect(cubit.state, ThemeMode.dark);
    expect((await settings.get()).themeMode, 'dark');
  });

  test('setting the mode already in use writes nothing', () async {
    final cubit = ThemeCubit(settings, initial: ThemeMode.dark);
    final states = <ThemeMode>[];
    cubit.stream.listen(states.add);

    await cubit.set(ThemeMode.dark);
    await Future<void>.delayed(Duration.zero);

    expect(states, isEmpty);
  });

  test('an unrecognised stored value falls back to dark', () {
    // A hand-edited database or a downgrade must not leave a blank window.
    expect(ThemeCubit.parse('chartreuse'), ThemeMode.dark);
    expect(ThemeCubit.parse(null), ThemeMode.dark);
    expect(ThemeCubit.parse('system'), ThemeMode.dark);
  });
}
