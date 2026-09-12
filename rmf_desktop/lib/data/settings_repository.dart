import 'package:bcrypt/bcrypt.dart';
import 'package:drift/drift.dart';

import '../domain/money.dart';
import '../services/whatsapp/meta_client.dart';
import '../services/whatsapp/mock_client.dart';
import '../services/whatsapp/whatsapp_client.dart';
import 'audit_repository.dart';
import 'cycle_repricing.dart';
import 'database.dart';
import 'seed.dart';

/// Gym settings, plans and sections — everything the owner can configure.
///
/// WhatsApp credentials live here too rather than in a .env file, because the
/// gym owner installs a packaged app and has no terminal to edit files in.
class SettingsRepository {
  SettingsRepository(this.db, {AuditRepository? audit})
      : _audit = audit ?? AuditRepository(db);

  final AppDatabase db;
  final AuditRepository _audit;

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
    int? actorId,
    DateTime? now,
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

    // Read before the write: the old price is half of what makes the log
    // worth keeping, and it is gone the moment the update lands.
    final previous = await (db.select(db.membershipPlans)
          ..where((p) => p.id.equals(id)))
        .getSingleOrNull();

    final priceMoved = previous != null && previous.priceMinor != priceMinor;
    var repriced = 0;

    // One transaction: a new price live against a roster still carrying the
    // old one is precisely the split state `cycle_repricing.dart` exists to
    // prevent, and the loop below can touch every member in the gym. The
    // member-side path in `MemberRepository.update` makes the same bargain.
    await db.transaction(() async {
      await (db.update(db.membershipPlans)..where((p) => p.id.equals(id)))
          .write(
        MembershipPlansCompanion(
          name: Value(name),
          description: Value(description),
          durationMonths: Value(durationMonths),
          priceMinor: Value(priceMinor),
          isActive: Value(isActive),
        ),
      );

      // Only when the price actually moved. Editing the price changes what the
      // whole roster on this plan is billed, so the cycles they are currently
      // in follow it; renaming a plan, or flipping it inactive, is
      // housekeeping and must leave the roster's bills alone. Cycles they have
      // paid into keep the price they paid — see `cycle_repricing.dart`.
      if (priceMoved) {
        repriced = await repriceOpenCyclesForPlan(db, planId: id, now: now);
      }
    });

    // Renaming a plan is housekeeping; re-pricing one moves money for every
    // member on it who has no fee of their own, which is the single most
    // far-reaching thing this screen can do.
    if (priceMoved) {
      await _audit.record(
        category: AuditCategory.billing,
        action: AuditAction.planPriceChanged,
        outcome: AuditOutcome.success,
        actorId: actorId,
        amountMinor: priceMinor,
        summary: '$name: plan price changed from '
            '${formatMinorUnits(previous.priceMinor)} to '
            '${formatMinorUnits(priceMinor)}',
        detail: [
          if (repriced > 0)
            '$repriced unpaid billing ${repriced == 1 ? 'cycle' : 'cycles'} '
                're-priced'
          else
            'No unpaid billing cycle needed re-pricing',
          'Members on their own custom fee are unaffected',
          'Paid and part-paid months keep the price that was charged',
        ],
      );
    }
  }

  /// Who a change to [planId]'s price would reach.
  ///
  /// Asked by the Settings screen before the owner commits, so the dialog can
  /// name a number rather than a vague category. Deliberately the same
  /// question [repriceOpenCyclesForPlan] answers — members enrolled on this
  /// plan, still active, split by whether they have a fee of their own — so
  /// the warning and the work cannot drift apart.
  Future<PlanPricingImpact> planPricingImpact(int planId) async {
    final enrolled = await (db.select(db.memberships)
          ..where((m) => m.planId.equals(planId) & m.endDate.isNull()))
        .get();
    if (enrolled.isEmpty) return const PlanPricingImpact();

    final active = {
      for (final m in await (db.select(db.members)
            ..where((m) =>
                m.id.isIn(enrolled.map((e) => e.memberId)) &
                m.deactivatedAt.isNull()))
          .get())
        m.id,
    };

    var following = 0;
    var custom = 0;
    for (final membership in enrolled) {
      if (!active.contains(membership.memberId)) continue;
      if (membership.feeOverrideMinor == null) {
        following++;
      } else {
        custom++;
      }
    }
    return PlanPricingImpact(followingPlanPrice: following, onCustomFee: custom);
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

/// How many members a plan price change would and would not move.
class PlanPricingImpact {
  const PlanPricingImpact({
    this.followingPlanPrice = 0,
    this.onCustomFee = 0,
  });

  /// Active members on the plan with no fee of their own. These are the ones
  /// whose unpaid bills follow the new price.
  final int followingPlanPrice;

  /// Active members on the plan who have their own fee, which outranks the
  /// plan's. Nothing about their billing changes.
  final int onCustomFee;

  bool get isEmpty => followingPlanPrice == 0 && onCustomFee == 0;
}
