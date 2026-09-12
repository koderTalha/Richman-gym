import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/data/settings_repository.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';

/// Leaving a trail when money moves.
///
/// Deactivating one member is recorded; re-pricing the whole roster was not.
/// A plan price edit silently rewrites what every member on it is asked for
/// next month, and until now the only evidence it happened was the number
/// itself having changed. When the owner asks in March why a member is being
/// billed 2500, "the price was raised on 10 January by Owner, and 14 open
/// cycles moved with it" is the answer, and nothing in the app could give it.
void main() {
  late AppDatabase db;
  late MemberRepository members;
  late SettingsRepository settings;
  late AuditRepository audit;
  late int adminId;
  late int monthlyId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    members = MemberRepository(db);
    settings = SettingsRepository(db);
    audit = AuditRepository(db);

    adminId = (await db.select(db.users).getSingle()).id;
    monthlyId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle())
        .id;

    await (db.update(db.membershipPlans)..where((p) => p.id.equals(monthlyId)))
        .write(const MembershipPlansCompanion(priceMinor: Value(150000)));
  });

  tearDown(() async => db.close());

  Future<int> joinOn(DateTime joiningDate, {String phone = '+923000000001'}) =>
      members.create(
        fullName: 'Ali Khan',
        phone: phone,
        planId: monthlyId,
        joiningDate: joiningDate,
      );

  Future<void> openCycleOn(DateTime day) =>
      BillingMaintenance(db).ensureCurrentPeriods(now: day);

  Future<List<AuditEvent>> eventsFor(String action) async =>
      (await audit.recent(limit: 200))
          .where((e) => e.action == action)
          .toList();

  Future<void> editMember(
    int memberId, {
    required String name,
    int? feeOverrideMinor,
    int? planId,
    DateTime? now,
  }) =>
      members.update(
        id: memberId,
        fullName: name,
        phone: '+923000000001',
        planId: planId ?? monthlyId,
        feeOverrideMinor: feeOverrideMinor,
        joiningDate: DateTime.utc(2026, 1, 6),
        actorId: adminId,
        now: now,
      );

  group('a member fee change', () {
    test('is recorded with the fee either side of it', () async {
      final memberId = await joinOn(DateTime.utc(2026, 1, 6));
      await openCycleOn(DateTime.utc(2026, 1, 6));

      await editMember(memberId,
          name: 'Ali Khan',
          feeOverrideMinor: 200000,
          now: DateTime.utc(2026, 1, 10));

      final events = await eventsFor(AuditAction.memberFeeChanged);
      expect(events, hasLength(1));

      final event = events.single;
      expect(event.category, AuditCategory.billing);
      expect(event.outcome, AuditOutcome.success);
      expect(event.memberId, memberId);
      expect(event.amountMinor, 200000, reason: 'the fee they now pay');
      expect(event.summary, contains('Rs. 1,500'));
      expect(event.summary, contains('Rs. 2,000'));
      expect(event.actorName, isNotNull,
          reason: 'who changed it is the point of recording it');
    });

    test('says how many bills moved with it', () async {
      final memberId = await joinOn(DateTime.utc(2026, 1, 6));
      await openCycleOn(DateTime.utc(2026, 1, 6));

      await editMember(memberId,
          name: 'Ali Khan',
          feeOverrideMinor: 200000,
          now: DateTime.utc(2026, 1, 10));

      final event = (await eventsFor(AuditAction.memberFeeChanged)).single;
      expect(event.detail, contains('1'),
          reason: 'their open January cycle was re-priced');
    });

    test('is not recorded when only the name changed', () async {
      final memberId = await joinOn(DateTime.utc(2026, 1, 6));
      await openCycleOn(DateTime.utc(2026, 1, 6));

      await editMember(memberId,
          name: 'Ali Khan Jr', now: DateTime.utc(2026, 1, 10));

      expect(await eventsFor(AuditAction.memberFeeChanged), isEmpty,
          reason: 'a pricing log nobody can trust is a pricing log full of '
              'edits that changed no price');
    });

    test('is recorded when an override is removed', () async {
      final memberId = await joinOn(DateTime.utc(2026, 1, 6));
      await editMember(memberId,
          name: 'Ali Khan',
          feeOverrideMinor: 200000,
          now: DateTime.utc(2026, 1, 2));
      await openCycleOn(DateTime.utc(2026, 1, 6));

      await editMember(memberId,
          name: 'Ali Khan', now: DateTime.utc(2026, 1, 10));

      final events = await eventsFor(AuditAction.memberFeeChanged);
      expect(events, hasLength(2));
      expect(events.first.summary, contains('Rs. 1,500'),
          reason: 'newest first — they are back on the plan price');
    });

    test('is recorded when a plan change moves what they pay', () async {
      final memberId = await joinOn(DateTime.utc(2026, 1, 6));
      await openCycleOn(DateTime.utc(2026, 1, 6));

      await settings.savePlan(
        name: 'Gold',
        durationMonths: 1,
        priceMinor: 300000,
        isActive: true,
      );
      final goldId = (await (db.select(db.membershipPlans)
                ..where((p) => p.name.equals('Gold')))
              .getSingle())
          .id;

      await editMember(memberId,
          name: 'Ali Khan', planId: goldId, now: DateTime.utc(2026, 1, 10));

      final event = (await eventsFor(AuditAction.memberFeeChanged)).single;
      expect(event.amountMinor, 300000);
      expect(event.summary, contains('Rs. 3,000'));
    });
  });

  group('a plan price change', () {
    test('is recorded with the price either side and the roster it moved',
        () async {
      final first = await joinOn(DateTime.utc(2026, 1, 6));
      final second =
          await joinOn(DateTime.utc(2026, 1, 6), phone: '+923000000002');
      await openCycleOn(DateTime.utc(2026, 1, 6));
      expect(second, isNot(first));

      await settings.savePlan(
        id: monthlyId,
        name: 'Monthly',
        durationMonths: 1,
        priceMinor: 250000,
        isActive: true,
        actorId: adminId,
        now: DateTime.utc(2026, 1, 10),
      );

      final event = (await eventsFor(AuditAction.planPriceChanged)).single;
      expect(event.category, AuditCategory.billing);
      expect(event.outcome, AuditOutcome.success);
      expect(event.amountMinor, 250000);
      expect(event.summary, contains('Monthly'));
      expect(event.summary, contains('Rs. 1,500'));
      expect(event.summary, contains('Rs. 2,500'));
      expect(event.detail, contains('2'),
          reason: 'both members had an open cycle that followed the price');
    });

    test('is not recorded when the plan is renamed but not re-priced',
        () async {
      await joinOn(DateTime.utc(2026, 1, 6));
      await openCycleOn(DateTime.utc(2026, 1, 6));

      await settings.savePlan(
        id: monthlyId,
        name: 'Monthly Standard',
        durationMonths: 1,
        priceMinor: 150000,
        isActive: true,
        actorId: adminId,
        now: DateTime.utc(2026, 1, 10),
      );

      expect(await eventsFor(AuditAction.planPriceChanged), isEmpty);
    });

    test('is not recorded when the plan is first created', () async {
      await settings.savePlan(
        name: 'Gold',
        durationMonths: 1,
        priceMinor: 300000,
        isActive: true,
        actorId: adminId,
      );

      expect(await eventsFor(AuditAction.planPriceChanged), isEmpty,
          reason: 'a new plan has no previous price to have moved from');
    });
  });
}
