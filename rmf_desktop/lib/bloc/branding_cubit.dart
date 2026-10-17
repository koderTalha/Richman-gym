import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:logging/logging.dart';

import '../data/settings_repository.dart';
import '../theme/branding_config.dart';

final _log = Logger('branding');

/// What the app is painted with, and what the Appearance screen is trying out.
///
/// Two configurations rather than one, because "preview before applying" is a
/// requirement: [draft] is what the whole app repaints itself with so the owner
/// sees a theme on real screens rather than a swatch, while [saved] is what is
/// on disk and what Cancel returns to. Nothing is written until [apply].
class BrandingState {
  const BrandingState({required this.saved, required this.draft});

  const BrandingState.settled(BrandingConfig config)
      : saved = config,
        draft = config;

  /// The configuration persisted in the settings row.
  final BrandingConfig saved;

  /// What the app is currently painted with — the draft while previewing,
  /// otherwise identical to [saved].
  final BrandingConfig draft;

  /// True while the owner is trying something they have not kept yet.
  bool get isPreviewing => draft != saved;

  BrandingState copyWith({BrandingConfig? saved, BrandingConfig? draft}) =>
      BrandingState(saved: saved ?? this.saved, draft: draft ?? this.draft);
}

/// Owns the gym's branding: the active theme, custom colours, logo and receipt
/// template.
///
/// Seeded from the database in main() rather than loaded here, for the same
/// reason [ThemeCubit] is: the first frame must already be the owner's chosen
/// brand instead of flashing crimson and correcting itself.
class BrandingCubit extends Cubit<BrandingState> {
  BrandingCubit(this._settings, {required BrandingConfig initial})
      : super(BrandingState.settled(initial));

  final SettingsRepository _settings;

  /// Repaints the app in [config] without saving it.
  void preview(BrandingConfig config) =>
      emit(state.copyWith(draft: config));

  /// Throws the preview away and repaints as whatever is on disk.
  void cancelPreview() => emit(BrandingState.settled(state.saved));

  /// Writes the draft to the settings row.
  ///
  /// The repaint has already happened (the draft is what the app is showing),
  /// so this only persists. A failed write leaves the owner looking at the
  /// theme they chose while the database still holds the old one — which is
  /// why the new state's `saved` is only advanced once the write succeeds, so
  /// a restart is honest about what was actually kept.
  Future<bool> apply() async {
    final draft = state.draft;
    try {
      await _settings.saveBranding(draft);
      emit(BrandingState.settled(draft));
      return true;
    } catch (e, s) {
      _log.severe('Could not save the appearance settings', e, s);
      return false;
    }
  }

  /// Saves [config] directly, with no preview step. Used by the logo and
  /// receipt-template controls, where there is nothing to preview in place.
  Future<bool> applyNow(BrandingConfig config) {
    emit(state.copyWith(draft: config));
    return apply();
  }
}
