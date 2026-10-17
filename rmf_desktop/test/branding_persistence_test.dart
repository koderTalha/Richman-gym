import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/bloc/branding_cubit.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';
import 'package:rich_man_fitness/theme/branding_config.dart';
import 'package:rich_man_fitness/theme/theme_preset.dart';

/// The theme has to survive a refresh, a logout, and a restart — which for this
/// app all mean the same thing: it is read back off the settings row.
void main() {
  late AppDatabase db;
  late SettingsRepository settings;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    settings = SettingsRepository(db);
    // The singleton the app seeds on first run.
    await db.into(db.gymSettings).insert(
        const GymSettingsCompanion(id: Value(1)),
        mode: InsertMode.insertOrIgnore);
  });

  tearDown(() => db.close());

  test('a fresh install reads as the original crimson', () async {
    final branding = await settings.branding();

    expect(branding.presetId, ThemePreset.richmanRed.id);
    expect(branding.receiptTemplate, ReceiptTemplate.classic);
    expect(branding.logoPath, isNull);
    expect(branding.effectivePreset.primary, const Color(0xFFE11D2E),
        reason: 'the gym must open in the red it has always had');
  });

  test('a chosen preset is read back after a restart', () async {
    await settings.saveBranding(
        const BrandingConfig(presetId: 'oceanTeal'));

    // A "restart" is a fresh repository over the same file.
    final reopened = await SettingsRepository(db).branding();

    expect(reopened.presetId, 'oceanTeal');
    expect(reopened.effectivePreset.primary, ThemePreset.oceanTeal.primary);
  });

  test('custom colours round-trip through hex storage', () async {
    const config = BrandingConfig(
      presetId: BrandingConfig.customId,
      custom: CustomColors(
        primary: Color(0xFF2563EB),
        accent: Color(0xFF7CA5FB),
        background: Color(0xFF0F172A),
        sidebar: Color(0xFF0B1220),
        surface: Color(0xFF16213C),
        textPrimary: Color(0xFFF5F5F7),
      ),
    );

    await settings.saveBranding(config);
    final reopened = await settings.branding();

    expect(reopened.isCustom, isTrue);
    expect(reopened.custom.primary, const Color(0xFF2563EB));
    expect(reopened.custom.sidebar, const Color(0xFF0B1220));
    expect(reopened.custom.textPrimary, const Color(0xFFF5F5F7));
  });

  test('clearing a custom colour actually clears it', () async {
    await settings.saveBranding(const BrandingConfig(
      presetId: BrandingConfig.customId,
      custom: CustomColors(primary: Color(0xFF2563EB)),
    ));
    expect((await settings.branding()).custom.primary, isNotNull);

    // The bug this guards: a Companion that omits the field leaves the old
    // value in place, and the owner's reset appears to do nothing.
    await settings.saveBranding(
        const BrandingConfig(presetId: BrandingConfig.customId));

    expect((await settings.branding()).custom.primary, isNull);
  });

  test('a malformed hex in the database does not stop the app opening',
      () async {
    // A hand-edited database, or one restored from a build that stored
    // something else. The app has to open; a colour is not worth a crash.
    await settings.update(const GymSettingsCompanion(
      themePreset: Value(BrandingConfig.customId),
      customPrimary: Value('not a colour'),
    ));

    final branding = await settings.branding();

    expect(branding.custom.primary, isNull);
    expect(branding.effectivePreset.primary, ThemePreset.fallback.primary,
        reason: 'an unreadable colour falls back rather than painting black');
  });

  test('an unknown preset id falls back to the default', () async {
    await settings.update(
        const GymSettingsCompanion(themePreset: Value('neonPink')));

    expect((await settings.branding()).presetId, ThemePreset.fallback.id);
  });

  test('the logo path is stored once and shared', () async {
    await settings.saveBranding(
        const BrandingConfig(logoPath: '/data/branding/logo-1.png'));

    final row = await settings.get();
    // The sidebar and the receipt renderer both read this one column; there is
    // deliberately no second place a logo can live.
    expect(row.logoPath, '/data/branding/logo-1.png');
    expect((await settings.branding()).logoPath,
        '/data/branding/logo-1.png');
  });

  group('the cubit', () {
    test('previewing repaints without saving', () async {
      final cubit = BrandingCubit(settings,
          initial: const BrandingConfig());

      cubit.preview(const BrandingConfig(presetId: 'blackGold'));

      expect(cubit.state.draft.presetId, 'blackGold');
      expect(cubit.state.saved.presetId, ThemePreset.fallback.id);
      expect(cubit.state.isPreviewing, isTrue);
      expect((await settings.branding()).presetId, ThemePreset.fallback.id,
          reason: 'a preview must not touch the database');
    });

    test('cancelling puts back what is on disk', () {
      final cubit = BrandingCubit(settings,
          initial: const BrandingConfig());

      cubit.preview(const BrandingConfig(presetId: 'blackGold'));
      cubit.cancelPreview();

      expect(cubit.state.draft.presetId, ThemePreset.fallback.id);
      expect(cubit.state.isPreviewing, isFalse);
    });

    test('applying writes it and settles', () async {
      final cubit = BrandingCubit(settings,
          initial: const BrandingConfig());

      cubit.preview(const BrandingConfig(presetId: 'royalPurple'));
      final saved = await cubit.apply();

      expect(saved, isTrue);
      expect(cubit.state.isPreviewing, isFalse);
      expect(cubit.state.saved.presetId, 'royalPurple');
      expect((await settings.branding()).presetId, 'royalPurple',
          reason: 'Apply is what reaches the disk');
    });

    test('a logout cannot lose an applied theme', () async {
      // Logging out disposes the blocs but not the database; the next sign-in
      // seeds from the row again.
      final cubit = BrandingCubit(settings,
          initial: const BrandingConfig());
      cubit.preview(const BrandingConfig(presetId: 'powerOrange'));
      await cubit.apply();
      await cubit.close();

      final afterLogin = await settings.branding();
      expect(afterLogin.presetId, 'powerOrange');
    });
  });

  group('hero photographs', () {
    test('a fresh install has neither', () async {
      final branding = await settings.branding();

      expect(branding.loginPhotoPath, isNull);
      expect(branding.dashboardPhotoPath, isNull);
    });

    test('each slot is stored separately', () async {
      // The whole reason these are two columns: a gym that puts its frontage
      // on the sign-in screen and its gym floor on the dashboard must not have
      // one overwrite the other.
      await settings.saveBranding(const BrandingConfig(
        loginPhotoPath: '/branding/photo-front.jpg',
        dashboardPhotoPath: '/branding/photo-floor.jpg',
      ));

      final branding = await settings.branding();
      expect(branding.loginPhotoPath, '/branding/photo-front.jpg');
      expect(branding.dashboardPhotoPath, '/branding/photo-floor.jpg');
    });

    test('clearing one leaves the other alone', () async {
      await settings.saveBranding(const BrandingConfig(
        loginPhotoPath: '/branding/photo-front.jpg',
        dashboardPhotoPath: '/branding/photo-floor.jpg',
      ));

      final cleared = (await settings.branding())
          .copyWith(clearLoginPhoto: true);
      await settings.saveBranding(cleared);

      final branding = await settings.branding();
      expect(branding.loginPhotoPath, isNull);
      expect(branding.dashboardPhotoPath, '/branding/photo-floor.jpg',
          reason: 'removing one photo must not remove the other');
    });

    test('a photo survives a restart', () async {
      final cubit = BrandingCubit(settings, initial: const BrandingConfig());
      await cubit.applyNow(
        const BrandingConfig(dashboardPhotoPath: '/branding/photo-floor.jpg'),
      );
      await cubit.close();

      expect((await settings.branding()).dashboardPhotoPath,
          '/branding/photo-floor.jpg');
    });

    test('a photo and a logo coexist', () async {
      // They share the branding directory and the same settings row, so the
      // one that saves last must not blank the others.
      await settings.saveBranding(const BrandingConfig(
        logoPath: '/branding/logo-1.png',
        loginPhotoPath: '/branding/photo-1.jpg',
        dashboardPhotoPath: '/branding/photo-2.jpg',
      ));

      final branding = await settings.branding();
      expect(branding.logoPath, '/branding/logo-1.png');
      expect(branding.loginPhotoPath, '/branding/photo-1.jpg');
      expect(branding.dashboardPhotoPath, '/branding/photo-2.jpg');
    });

    test('changing a photo does not disturb the chosen theme', () async {
      await settings.saveBranding(const BrandingConfig(
        presetId: 'oceanTeal',
        loginPhotoPath: '/branding/photo-1.jpg',
      ));

      final swapped = (await settings.branding())
          .copyWith(loginPhotoPath: '/branding/photo-2.jpg');
      await settings.saveBranding(swapped);

      final branding = await settings.branding();
      expect(branding.loginPhotoPath, '/branding/photo-2.jpg');
      expect(branding.presetId, 'oceanTeal');
    });
  });
}
