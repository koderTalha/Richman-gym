import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart' show ThemeMode;
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';

import '../data/database.dart';
import '../data/settings_repository.dart';

final _log = Logger('theme');

/// Holds the light/dark choice and writes it back to the settings row.
///
/// Seeded from the database in main() rather than loaded here, so the first
/// frame is already painted in the owner's chosen theme instead of flashing
/// dark and correcting itself.
class ThemeCubit extends Cubit<ThemeMode> {
  ThemeCubit(this._settings, {ThemeMode initial = ThemeMode.dark})
      : super(initial);

  final SettingsRepository _settings;

  Future<void> toggle() =>
      set(state == ThemeMode.dark ? ThemeMode.light : ThemeMode.dark);

  Future<void> set(ThemeMode mode) async {
    if (mode == state) return;
    // Repaint first: the owner should not wait on a disk write to see the
    // theme change, and a failed write is not worth blocking the UI for.
    emit(mode);
    try {
      await _settings.update(GymSettingsCompanion(themeMode: Value(mode.name)));
    } catch (e, s) {
      _log.severe('Could not save the theme preference', e, s);
    }
  }

  /// Anything unrecognised falls back to dark, which is what the gym ran
  /// before this setting existed.
  static ThemeMode parse(String? stored) =>
      stored == ThemeMode.light.name ? ThemeMode.light : ThemeMode.dark;
}
