import 'package:bcrypt/bcrypt.dart';
import 'package:drift/drift.dart';

import '../domain/phone.dart';
import 'database.dart';

/// Test members modelled on the owner's real ledger (names, 03xx numbers,
/// enrolment numbers), deliberately spread across PAID / DUE / EXPIRED /
/// INACTIVE so the dashboard and filters have something meaningful to show.
///
/// `paidMonthsAgo` lists which monthly cycles already have a payment, counted
/// back from the current month (0 = this month).
const _seedMembers = [
  (2, 'Member One', '0300-0000001', 'Male', 'Monthly', [0, 1, 2], false),
  (3, 'Member Two', '0300-0000002', 'Male', 'Monthly', [1, 2], false),
  (5, 'Member Three', '0300-0000003', 'Male', 'Monthly', [0, 1], false),
  (6, 'Member Four', '0300-0000004', 'Male', 'Quarterly', [0], false),
  (8, 'Member Five', '0300-0000005', 'Male', 'Monthly', [2, 3], false),
  (13, 'Member Six', '0300-0000006', 'Male', 'Monthly', [0, 1, 2], false),
  (14, 'Member Seven', '0300-0000007', 'Male', 'Monthly', [1], false),
  (17, 'Member Eight', '0300-0000008', 'Male', 'Monthly', [0], false),
  (18, 'Member Nine', '0300-0000009', 'Male', '6 Months', [0], false),
  (19, 'Member Ten', '0300-0000010', 'Male', 'Monthly', [3, 4], false),
  (20, 'Member Eleven', '0300-0000011', 'Male', 'Monthly', [0, 1], false),
  (24, 'Member Twelve', '0300-0000012', 'Male', 'Monthly', <int>[], true),
  (25, 'Member Thirteen', '0300-0000013', 'Male', 'Monthly', [1, 2], false),
  (26, 'Member Fourteen', '0300-0000014', 'Male', 'Annual', [0], false),
  (28, 'Member Fifteen', '0300-0000015', 'Male', 'Monthly', [0, 1], false),
  (30, 'Member Sixteen', '0300-0000016', 'Male', 'Monthly', <int>[], false),
  (32, 'Member Seventeen', '0300-0000017', 'Male', 'Monthly', [2], false),
  (33, 'Member Eighteen', '0300-0000018', 'Male', 'Monthly', [0, 1, 2], false),
  (41, 'Member Nineteen', '0300-0000019', 'Female', 'Monthly', [0, 1], false),
  (42, 'Member Twenty', '0300-0000020', 'Female', 'Quarterly', <int>[], false),
];

DateTime _monthStart(int monthsAgo, DateTime now) =>
    DateTime.utc(now.year, now.month - monthsAgo, 1);

DateTime _addMonths(DateTime date, int months) =>
    DateTime.utc(date.year, date.month + months, date.day);

/// Idempotent: safe to run on every launch. Only fills in what is missing.
Future<void> seedDatabase(
  AppDatabase db, {
  String adminEmail = 'admin@richmanfitness.local',
  String adminPassword = 'RichMan#2026',
  String adminName = 'Gym Owner',
  // Off by default: a real installation must start with the gym's own members,
  // not twenty invented ones. Tests opt in explicitly.
  bool includeSampleMembers = false,
}) async {
  // --- Admin user ---------------------------------------------------------
  final existingAdmin = await (db.select(db.users)
        ..where((u) => u.email.equals(adminEmail)))
      .getSingleOrNull();

  final adminId = existingAdmin?.id ??
      await db.into(db.users).insert(
            UsersCompanion.insert(
              name: adminName,
              email: adminEmail,
              passwordHash: BCrypt.hashpw(adminPassword, BCrypt.gensalt()),
            ),
          );

  // --- Settings singleton -------------------------------------------------
  final settings =
      await (db.select(db.gymSettings)..where((s) => s.id.equals(1)))
          .getSingleOrNull();
  if (settings == null) {
    await db.into(db.gymSettings).insert(
          GymSettingsCompanion.insert(
            id: const Value(1),
            phone: const Value('+923000000021'),
            whatsappPhone: const Value('+923000000021'),
            email: const Value('info@richmanfitness.local'),
            address: const Value('Main Boulevard, Lahore, Pakistan'),
            openingHours: const Value('Mon-Sat: 6:00 AM - 11:00 PM'),
          ),
        );
  }

  // --- Membership plans ---------------------------------------------------
  const planSpecs = [
    ('Monthly', 'Full gym access, billed every month.', 1, 300000),
    ('Quarterly', 'Three months of access at a reduced rate.', 3, 800000),
    ('6 Months', 'Half-year membership, best mid-term value.', 6, 1500000),
    ('Annual', 'Twelve months at our lowest monthly rate.', 12, 2800000),
  ];
  for (final (name, description, months, priceMinor) in planSpecs) {
    final existing = await (db.select(db.membershipPlans)
          ..where((p) => p.name.equals(name)))
        .getSingleOrNull();
    if (existing == null) {
      await db.into(db.membershipPlans).insert(
            MembershipPlansCompanion.insert(
              name: name,
              description: Value(description),
              durationMonths: months,
              priceMinor: priceMinor,
            ),
          );
    }
  }

  if (!includeSampleMembers) return;

  // --- Sample members with payment history --------------------------------
  final anyMember = await (db.select(db.members)..limit(1)).getSingleOrNull();
  if (anyMember != null) return; // already seeded

  final plansByName = {
    for (final p in await db.select(db.membershipPlans).get()) p.name: p
  };
  final now = DateTime.now().toUtc();

  for (final (code, name, rawPhone, gender, planName, paidMonths, inactive)
      in _seedMembers) {
    final plan = plansByName[planName]!;
    final phone = normalizePhone(rawPhone);
    if (phone == null) continue;

    final earliest = paidMonths.isEmpty
        ? 1
        : paidMonths.reduce((a, b) => a > b ? a : b);
    final joiningDate = _monthStart(earliest, now);

    final memberId = await db.into(db.members).insert(
          MembersCompanion.insert(
            memberCode: code,
            fullName: name,
            phone: phone,
            phoneRaw: Value(rawPhone),
            gender: Value(gender),
            joiningDate: joiningDate,
            deactivatedAt: Value(inactive ? now : null),
          ),
        );

    final membershipId = await db.into(db.memberships).insert(
          MembershipsCompanion.insert(
            memberId: memberId,
            planId: plan.id,
            startDate: joiningDate,
          ),
        );

    for (final monthsAgo in paidMonths) {
      final periodStart = _monthStart(monthsAgo, now);
      final periodId = await db.into(db.membershipPeriods).insert(
            MembershipPeriodsCompanion.insert(
              membershipId: membershipId,
              periodStart: periodStart,
              periodEnd: _addMonths(periodStart, plan.durationMonths),
              expectedAmountMinor: plan.priceMinor,
            ),
          );

      await db.into(db.payments).insert(
            PaymentsCompanion.insert(
              memberId: memberId,
              membershipPeriodId: Value(periodId),
              amountMinor: plan.priceMinor,
              method: monthsAgo.isEven
                  ? PaymentMethod.cash
                  : PaymentMethod.easypaisa,
              paymentDate: periodStart.add(const Duration(days: 4)),
              source: const Value(PaymentSource.imported),
              recordedById: adminId,
              idempotencyKey:
                  'seed-$code-${periodStart.toIso8601String().substring(0, 7)}',
            ),
          );
    }

    // An unpaid current cycle so these members show as DUE.
    if (!inactive && !paidMonths.contains(0)) {
      final periodStart = _monthStart(0, now);
      await db.into(db.membershipPeriods).insert(
            MembershipPeriodsCompanion.insert(
              membershipId: membershipId,
              periodStart: periodStart,
              periodEnd: _addMonths(periodStart, plan.durationMonths),
              expectedAmountMinor: plan.priceMinor,
            ),
          );
    }
  }
}
