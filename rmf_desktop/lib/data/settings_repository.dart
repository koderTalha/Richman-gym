import 'package:bcrypt/bcrypt.dart';
import 'package:drift/drift.dart';

import '../services/whatsapp/meta_client.dart';
import '../services/whatsapp/mock_client.dart';
import '../services/whatsapp/whatsapp_client.dart';
import 'database.dart';
import 'seed.dart';

/// Gym settings, plans and sections — everything the owner can configure.
///
/// WhatsApp credentials live here too rather than in a .env file, because the
/// gym owner installs a packaged app and has no terminal to edit files in.
class SettingsRepository {
  SettingsRepository(this.db);

  final AppDatabase db;

  Future<GymSetting> get() =>
      (db.select(db.gymSettings)..where((s) => s.id.equals(1))).getSingle();

  Future<void> update(GymSettingsCompanion changes) async {
    await (db.update(db.gymSettings)..where((s) => s.id.equals(1)))
        .write(changes);
  }

  // --- Membership plans ----------------------------------------------------

  Future<List<MembershipPlan>> plans({bool activeOnly = false}) {
    final query = db.select(db.membershipPlans)
      ..orderBy([(p) => OrderingTerm(expression: p.durationMonths)]);
    if (activeOnly) query.where((p) => p.isActive.equals(true));
    return query.get();
  }

  Future<void> savePlan({
    int? id,
    required String name,
    String? description,
    required int durationMonths,
    required int priceMinor,
    required bool isActive,
  }) async {
    if (id == null) {
      await db.into(db.membershipPlans).insert(
            MembershipPlansCompanion.insert(
              name: name,
              description: Value(description),
              durationMonths: durationMonths,
              priceMinor: priceMinor,
              isActive: Value(isActive),
            ),
          );
      return;
    }

    await (db.update(db.membershipPlans)..where((p) => p.id.equals(id))).write(
      MembershipPlansCompanion(
        name: Value(name),
        description: Value(description),
        durationMonths: Value(durationMonths),
        priceMinor: Value(priceMinor),
        isActive: Value(isActive),
      ),
    );
  }

  /// Plans are deactivated rather than deleted, because memberships reference
  /// them and their historical prices must stay resolvable.
  Future<void> setPlanActive(int id, bool active) async {
    await (db.update(db.membershipPlans)..where((p) => p.id.equals(id)))
        .write(MembershipPlansCompanion(isActive: Value(active)));
  }

  Future<bool> planInUse(int id) async {
    final rows = await (db.select(db.memberships)
          ..where((m) => m.planId.equals(id))
          ..limit(1))
        .get();
    return rows.isNotEmpty;
  }

  // --- WhatsApp ------------------------------------------------------------

  Future<WhatsAppConfig> whatsAppConfig() async {
    final settings = await get();
    return WhatsAppConfig(
      kind: settings.whatsappProvider,
      phoneNumberId: settings.whatsappPhoneNumberId,
      accessToken: settings.whatsappAccessToken,
    );
  }

  /// Checks saved Meta credentials without sending a message.
  Future<MetaVerification> testWhatsAppCredentials({
    String? phoneNumberId,
    String? accessToken,
  }) async {
    final settings = await get();
    final id = phoneNumberId ?? settings.whatsappPhoneNumberId;
    final token = accessToken ?? settings.whatsappAccessToken;

    if (id == null || id.isEmpty || token == null || token.isEmpty) {
      return MetaVerification.failure(
          'Enter both the Phone Number ID and the Access Token first.');
    }

    return MetaWhatsAppClient(phoneNumberId: id, accessToken: token)
        .verifyCredentials();
  }

  // --- Account -------------------------------------------------------------

  /// Changes a user's password after confirming the current one.
  ///
  /// Returns null on success, or a message explaining why it was rejected.
  Future<String?> changePassword({
    required int userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    if (newPassword.length < 8) {
      return 'The new password must be at least 8 characters.';
    }

    // Otherwise the forced first-run change can be satisfied by typing the
    // shipped password back in, which changes nothing at all.
    if (newPassword == defaultAdminPassword) {
      return 'That is the password the app is installed with. '
          'Choose a different one.';
    }

    final user = await (db.select(db.users)..where((u) => u.id.equals(userId)))
        .getSingleOrNull();
    if (user == null) return 'That account no longer exists.';

    if (!BCrypt.checkpw(currentPassword, user.passwordHash)) {
      return 'The current password is incorrect.';
    }

    await (db.update(db.users)..where((u) => u.id.equals(userId))).write(
      UsersCompanion(
        passwordHash: Value(BCrypt.hashpw(newPassword, BCrypt.gensalt())),
      ),
    );
    return null;
  }

  /// Builds the client for the currently configured provider.
  /// Throws when Meta is selected but not fully configured, which surfaces as a
  /// recorded WhatsApp failure rather than a crash.
  Future<WhatsAppClient> buildClient() async {
    final config = await whatsAppConfig();

    switch (config.kind) {
      case WhatsAppProviderKind.meta:
        if (!config.isConfigured) {
          throw StateError(
              'WhatsApp is set to Meta but is missing: ${config.missing.join(", ")}');
        }
        return MetaWhatsAppClient(
          phoneNumberId: config.phoneNumberId!,
          accessToken: config.accessToken!,
        );
      case WhatsAppProviderKind.mock:
      case WhatsAppProviderKind.manual:
        final settings = await get();
        return MockWhatsAppClient(forceFailure: settings.whatsappMockFails);
    }
  }
}
