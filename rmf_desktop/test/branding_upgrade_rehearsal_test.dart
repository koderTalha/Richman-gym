// Upgrade rehearsal: a v12 database with real-looking gym data, opened by the
// new code, checked that nothing moved. Mirrors what happens on the owner's
// machine when the installer replaces the app.
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';
import 'package:rich_man_fitness/theme/branding_config.dart';
import 'package:sqlite3/sqlite3.dart';

void main() {
  test('a v12 gym database upgrades to the current schema with its money '
      'intact', () async {
    final dir = await Directory.systemTemp.createTemp('rmf-upgrade-sim');
    addTearDown(() => dir.delete(recursive: true));
    final file = File(p.join(dir.path, 'gym.sqlite'));

    // 1. Build a v12 database by letting the CURRENT code create it, then
    //    rewinding user_version and dropping every column added since — the
    //    closest thing to "what the v12 release left on disk".
    final seedDb = AppDatabase.forTesting(NativeDatabase(file));
    await seedDb.customSelect('SELECT 1').get();
    await seedDb.close();

    final raw = sqlite3.open(file.path);
    for (final col in [
      'theme_preset', 'custom_primary', 'custom_accent', 'custom_background',
      'custom_sidebar', 'custom_surface', 'custom_text_primary',
      'receipt_template',
      // v14's hero photographs.
      'login_photo_path', 'dashboard_photo_path',
    ]) {
      raw.execute('ALTER TABLE gym_settings DROP COLUMN $col');
    }
    // Real-looking gym data, as a working install would hold. Inserted rather
    // than updated: forTesting() creates the schema but seeds no rows.
    raw.execute("INSERT INTO gym_settings (id, gym_name, receipt_prefix, "
        "theme_mode) VALUES (1, 'Rich Man Fitness', 'RMF', 'dark')");
    raw.execute("INSERT INTO membership_plans (id, name, duration_months, price_minor) "
        "VALUES (90, 'Student Package', 1, 250000)");
    raw.execute("INSERT INTO members (id, member_code, full_name, phone, joining_date) "
        "VALUES (90, 414, 'Test Overdue', '+923000000101', 1772323200)");
    raw.execute('PRAGMA user_version = 12');
    final before = raw.select('SELECT COUNT(*) c FROM members').first['c'];
    raw.close();

    // 2. The upgrade: the new build opens the old file.
    final db = AppDatabase.forTesting(NativeDatabase(file));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    final version = await db.customSelect('PRAGMA user_version')
        .map((r) => r.read<int>('user_version')).getSingle();
    expect(version, db.schemaVersion, reason: 'the migration ran');

    // 3. The data is where the owner left it.
    final members = await db.select(db.members).get();
    expect(members.length, before);
    final overdue = members.firstWhere((m) => m.memberCode == 414);
    expect(overdue.fullName, 'Test Overdue');
    expect(overdue.phone, '+923000000101');

    final plan = await (db.select(db.membershipPlans)
          ..where((t) => t.id.equals(90)))
        .getSingle();
    expect(plan.priceMinor, 250000, reason: 'the fee is untouched');

    // 4. And the app opens looking exactly as it did.
    final branding = await SettingsRepository(db).branding();
    expect(branding.presetId, 'richmanRed');
    expect(branding.receiptTemplate, ReceiptTemplate.classic);
    expect(branding.logoPath, isNull);
    // The upgrade must not invent artwork the gym never chose: both hero slots
    // stay empty, so the owner's sign-in and dashboard look exactly as before.
    expect(branding.loginPhotoPath, isNull);
    expect(branding.dashboardPhotoPath, isNull);
    expect((await SettingsRepository(db).get()).themeMode, 'dark');

    // 5. The new settings are writable afterwards.
    await SettingsRepository(db)
        .saveBranding(const BrandingConfig(presetId: 'oceanTeal'));
    expect((await SettingsRepository(db).branding()).presetId, 'oceanTeal');
  });
}
