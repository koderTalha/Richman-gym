import 'package:drift/drift.dart';

import '../domain/member_status.dart';
import 'database.dart';

/// A member joined with everything the list and profile screens need, plus the
/// status derived from real payment records.
class MemberRow {
  const MemberRow({
    required this.member,
    required this.membership,
    required this.plan,
    required this.status,
    required this.feeMinor,
    required this.paidUntil,
  });

  final Member member;
  final Membership? membership;
  final MembershipPlan? plan;
  final MemberStatus status;

  /// Effective fee: the member's override if set, otherwise the plan price.
  final int? feeMinor;

  /// End of the latest paid cycle — when money is owed again.
  final DateTime? paidUntil;

  int get id => member.id;
}

enum MemberFilter { all, active, paid, due, expiringSoon, inactive }

extension MemberFilterLabel on MemberFilter {
  String get label => switch (this) {
        MemberFilter.all => 'All',
        MemberFilter.active => 'Active',
        MemberFilter.paid => 'Paid',
        MemberFilter.due => 'Due',
        MemberFilter.expiringSoon => 'Expiring Soon',
        MemberFilter.inactive => 'Inactive',
      };
}

const _expiringWindowDays = 7;

class MemberRepository {
  MemberRepository(this.db);

  final AppDatabase db;

  /// Builds the status view for every member in one pass.
  ///
  /// Rather than issuing a query per member, this loads the active membership
  /// and its billing cycles for all members at once and joins them in memory —
  /// which keeps the members screen responsive with a few thousand members.
  /// [now] exists so time-dependent status can be tested; production leaves it
  /// unset and uses the real clock.
  Future<List<MemberRow>> list({
    String? search,
    MemberFilter filter = MemberFilter.all,
    DateTime? now,
  }) async {
    final term = search?.trim();

    var membersQuery = db.select(db.members)
      ..orderBy([(m) => OrderingTerm(expression: m.memberCode)]);

    if (term != null && term.isNotEmpty) {
      final code = int.tryParse(term);
      membersQuery = membersQuery
        ..where((m) =>
            m.fullName.lower().contains(term.toLowerCase()) |
            m.phone.contains(term) |
            (code != null ? m.memberCode.equals(code) : const Constant(false)));
    }

    final at = now?.toUtc() ?? DateTime.now().toUtc();
    final rows = await _buildRows(await membersQuery.get(), now: at);
    return _applyFilter(rows, filter, at);
  }

  /// Joins members with their active enrolment, cycles and payment state.
  ///
  /// Scoped to whatever members are passed in, so looking up a single member
  /// costs one member's worth of work rather than the whole roster.
  Future<List<MemberRow>> _buildRows(
    List<Member> memberRows, {
    DateTime? now,
  }) async {
    if (memberRows.isEmpty) return const [];

    final memberIds = memberRows.map((m) => m.id).toList();

    final plans = {
      for (final p in await db.select(db.membershipPlans).get()) p.id: p
    };

    // Active enrolment (endDate == null) per member.
    final activeMemberships = await (db.select(db.memberships)
          ..where((m) => m.memberId.isIn(memberIds) & m.endDate.isNull()))
        .get();
    final membershipByMember = {
      for (final m in activeMemberships) m.memberId: m,
    };

    final membershipIds = activeMemberships.map((m) => m.id).toList();

    final periods = membershipIds.isEmpty
        ? <MembershipPeriod>[]
        : await (db.select(db.membershipPeriods)
              ..where((p) => p.membershipId.isIn(membershipIds))
              ..orderBy([(p) => OrderingTerm(expression: p.periodStart)]))
            .get();

    // Which cycles have at least one payment.
    final periodIds = periods.map((p) => p.id).toList();
    final paidPeriodIds = <int>{};
    if (periodIds.isNotEmpty) {
      final paid = await (db.selectOnly(db.payments)
            ..addColumns([db.payments.membershipPeriodId])
            ..where(db.payments.membershipPeriodId.isIn(periodIds))
            ..groupBy([db.payments.membershipPeriodId]))
          .get();
      for (final row in paid) {
        final id = row.read(db.payments.membershipPeriodId);
        if (id != null) paidPeriodIds.add(id);
      }
    }

    final periodsByMembership = <int, List<MembershipPeriod>>{};
    for (final period in periods) {
      periodsByMembership.putIfAbsent(period.membershipId, () => []).add(period);
    }

    final at = now ?? DateTime.now().toUtc();

    return memberRows.map((member) {
      final membership = membershipByMember[member.id];
      final plan = membership == null ? null : plans[membership.planId];
      final memberPeriods = periodsByMembership[membership?.id] ?? const [];

      final statusPeriods = memberPeriods
          .map((p) => StatusPeriod(
                periodStart: p.periodStart,
                periodEnd: p.periodEnd,
                isPaid: paidPeriodIds.contains(p.id),
              ))
          .toList();

      final paidEnds = statusPeriods.where((p) => p.isPaid).map((p) => p.periodEnd);

      return MemberRow(
        member: member,
        membership: membership,
        plan: plan,
        status: deriveMemberStatus(
          deactivatedAt: member.deactivatedAt,
          periods: statusPeriods,
          now: at,
        ),
        feeMinor: membership == null
            ? null
            : (membership.feeOverrideMinor ?? plan?.priceMinor),
        paidUntil: paidEnds.isEmpty
            ? null
            : paidEnds.reduce((a, b) => a.isAfter(b) ? a : b),
      );
    }).toList();
  }

  List<MemberRow> _applyFilter(
    List<MemberRow> rows,
    MemberFilter filter,
    DateTime now,
  ) {
    switch (filter) {
      case MemberFilter.all:
        return rows;
      case MemberFilter.active:
        return rows.where((r) => r.status != MemberStatus.inactive).toList();
      case MemberFilter.inactive:
        return rows.where((r) => r.status == MemberStatus.inactive).toList();
      case MemberFilter.paid:
        return rows.where((r) => r.status == MemberStatus.paid).toList();
      case MemberFilter.due:
        return rows
            .where((r) =>
                r.status == MemberStatus.due || r.status == MemberStatus.expired)
            .toList();
      case MemberFilter.expiringSoon:
        final cutoff = now.add(const Duration(days: _expiringWindowDays));
        return rows
            .where((r) =>
                r.status == MemberStatus.paid &&
                r.paidUntil != null &&
                !r.paidUntil!.isAfter(cutoff))
            .toList();
    }
  }

  Future<MemberRow?> byId(int id, {DateTime? now}) async {
    final member = await (db.select(db.members)..where((m) => m.id.equals(id)))
        .getSingleOrNull();
    if (member == null) return null;

    final rows = await _buildRows([member], now: now?.toUtc());
    return rows.isEmpty ? null : rows.first;
  }

  Future<int> nextMemberCode() async {
    final result = await (db.selectOnly(db.members)
          ..addColumns([db.members.memberCode.max()]))
        .getSingleOrNull();
    final highest = result?.read(db.members.memberCode.max()) ?? 0;
    return highest + 1;
  }

  Future<Member?> findByPhone(String phone) =>
      (db.select(db.members)..where((m) => m.phone.equals(phone)))
          .getSingleOrNull();

  /// Creates the member and their opening enrolment together, so a member can
  /// never exist without a plan (which would block recording payments).
  Future<int> create({
    required String fullName,
    required String phone,
    String? phoneRaw,
    String? email,
    String? gender,
    String? address,
    String? emergencyContact,
    required int planId,
    int? feeOverrideMinor,
    required DateTime joiningDate,
  }) async {
    return db.transaction(() async {
      final memberId = await db.into(db.members).insert(
            MembersCompanion.insert(
              memberCode: await nextMemberCode(),
              fullName: fullName,
              phone: phone,
              phoneRaw: Value(phoneRaw),
              email: Value(email),
              gender: Value(gender),
              address: Value(address),
              emergencyContact: Value(emergencyContact),
              joiningDate: joiningDate,
            ),
          );

      await db.into(db.memberships).insert(
            MembershipsCompanion.insert(
              memberId: memberId,
              planId: planId,
              feeOverrideMinor: Value(feeOverrideMinor),
              startDate: joiningDate,
            ),
          );

      return memberId;
    });
  }

  Future<void> update({
    required int id,
    required String fullName,
    required String phone,
    String? phoneRaw,
    String? email,
    String? gender,
    String? address,
    String? emergencyContact,
    required int planId,
    int? feeOverrideMinor,
    required DateTime joiningDate,
  }) async {
    await db.transaction(() async {
      await (db.update(db.members)..where((m) => m.id.equals(id))).write(
        MembersCompanion(
          fullName: Value(fullName),
          phone: Value(phone),
          phoneRaw: Value(phoneRaw),
          email: Value(email),
          gender: Value(gender),
          address: Value(address),
          emergencyContact: Value(emergencyContact),
          joiningDate: Value(joiningDate),
        ),
      );

      final active = await (db.select(db.memberships)
            ..where((m) => m.memberId.equals(id) & m.endDate.isNull()))
          .getSingleOrNull();

      if (active == null) {
        await db.into(db.memberships).insert(
              MembershipsCompanion.insert(
                memberId: id,
                planId: planId,
                feeOverrideMinor: Value(feeOverrideMinor),
                startDate: joiningDate,
              ),
            );
        return;
      }

      // Changing plan closes the current enrolment and opens a new one so the
      // member's history is preserved rather than rewritten.
      if (active.planId != planId) {
        await (db.update(db.memberships)..where((m) => m.id.equals(active.id)))
            .write(MembershipsCompanion(endDate: Value(DateTime.now().toUtc())));

        await db.into(db.memberships).insert(
              MembershipsCompanion.insert(
                memberId: id,
                planId: planId,
                feeOverrideMinor: Value(feeOverrideMinor),
                startDate: DateTime.now().toUtc(),
              ),
            );
      } else if (active.feeOverrideMinor != feeOverrideMinor) {
        await (db.update(db.memberships)..where((m) => m.id.equals(active.id)))
            .write(MembershipsCompanion(
                feeOverrideMinor: Value(feeOverrideMinor)));
      }
    });
  }

  /// Soft deactivation only — payments and receipts must survive.
  Future<void> setActive(int id, bool active) async {
    await (db.update(db.members)..where((m) => m.id.equals(id))).write(
      MembersCompanion(
        deactivatedAt: Value(active ? null : DateTime.now().toUtc()),
      ),
    );
  }


  Future<List<MembershipPlan>> plans() => (db.select(db.membershipPlans)
        ..where((p) => p.isActive.equals(true))
        ..orderBy([(p) => OrderingTerm(expression: p.durationMonths)]))
      .get();
}
