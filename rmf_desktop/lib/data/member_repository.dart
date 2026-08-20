import 'package:drift/drift.dart';

import '../domain/member_status.dart';
import '../domain/name.dart';
import 'audit_repository.dart';
import 'database.dart';
import 'membership_queries.dart';

/// The outcome of trying to delete a member. Typed, so the UI never has to
/// read a message to work out what happened.
sealed class MemberDeleteResult {
  const MemberDeleteResult();
}

class MemberDeleted extends MemberDeleteResult {
  const MemberDeleted(this.memberName);
  final String memberName;
}

/// The member has money recorded against them, so they are kept.
///
/// Deactivating is the answer for somebody who has left: the gym's revenue
/// history, receipts and exports all depend on their payments continuing to
/// exist. Deleting is for the mistake — the duplicate import, the member
/// entered twice — which by definition has no payments.
class MemberDeleteRefused extends MemberDeleteResult {
  const MemberDeleteRefused({
    required this.memberName,
    required this.paymentCount,
  });

  final String memberName;
  final int paymentCount;

  String get message => '$memberName has $paymentCount '
      '${paymentCount == 1 ? 'payment' : 'payments'} recorded. Deactivate them '
      'instead, or delete the payments first.';
}

class MemberDeleteNotFound extends MemberDeleteResult {
  const MemberDeleteNotFound();

  String get message => 'That member no longer exists.';
}

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

/// The one member in [candidates] who is the person called [fullName], or null.
///
/// Comparison goes through [namesMatch], which the ledger importer uses too.
Member? matchByName(Iterable<Member> candidates, String fullName) {
  for (final member in candidates) {
    if (namesMatch(member.fullName, fullName)) return member;
  }
  return null;
}

class MemberRepository {
  MemberRepository(this.db, {AuditRepository? audit})
      : _audit = audit ?? AuditRepository(db);

  final AppDatabase db;

  /// Member deletions and deactivations are exactly the changes the owner will
  /// later want to account for, so they are recorded rather than left to be
  /// inferred from a member who is simply no longer there.
  final AuditRepository _audit;

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
      // Escaped, so a "%" typed into the search box matches a literal percent
      // sign rather than expanding to every member on the roster.
      final pattern = '%${escapeLikePattern(term.toLowerCase())}%';
      membersQuery = membersQuery
        ..where((m) =>
            m.fullName.lower().like(pattern, escapeChar: r'\') |
            m.phone.like(pattern, escapeChar: r'\') |
            (code != null ? m.memberCode.equals(code) : const Constant(false)));
    }

    final at = now?.toUtc() ?? DateTime.now().toUtc();
    final rows = await _buildRows(await membersQuery.get(), now: at);
    return _applyFilter(rows, filter, at);
  }

  /// Joins members with their current enrolment, cycles and payment state.
  ///
  /// Scoped to whatever members are passed in, so looking up a single member
  /// costs one member's worth of work rather than the whole roster.
  ///
  /// The plan and fee come from the member's *open* enrolment, but the billing
  /// cycles come from *all* of their enrolments. Changing plan closes one
  /// enrolment and opens another, and the cycles the member already paid stay
  /// attached to the closed one — reading only the open enrolment made a
  /// fully-paid member read DUE the moment their plan was changed, with the
  /// money still sitting in the database.
  Future<List<MemberRow>> _buildRows(
    List<Member> memberRows, {
    DateTime? now,
  }) async {
    if (memberRows.isEmpty) return const [];

    final memberIds = memberRows.map((m) => m.id).toList();

    final plans = {
      for (final p in await db.select(db.membershipPlans).get()) p.id: p
    };

    final memberships = await (db.select(db.memberships)
          ..where((m) => m.memberId.isIn(memberIds))
          ..orderBy([(m) => OrderingTerm(expression: m.id)]))
        .get();

    // The open enrolment (endDate == null) is what the member is on *now*.
    // Iterating in id order means the newest wins if a legacy database holds
    // more than one, rather than the screen failing outright.
    final membershipByMember = <int, Membership>{};
    final memberByMembership = <int, int>{};
    for (final membership in memberships) {
      memberByMembership[membership.id] = membership.memberId;
      if (membership.endDate == null) {
        membershipByMember[membership.memberId] = membership;
      }
    }

    final membershipIds = memberships.map((m) => m.id).toList();

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

    final periodsByMember = <int, List<MembershipPeriod>>{};
    for (final period in periods) {
      final memberId = memberByMembership[period.membershipId];
      if (memberId == null) continue;
      periodsByMember.putIfAbsent(memberId, () => []).add(period);
    }

    final at = now ?? DateTime.now().toUtc();

    return memberRows.map((member) {
      final membership = membershipByMember[member.id];
      final plan = membership == null ? null : plans[membership.planId];

      final statusPeriods = _mergeCycles(
        periodsByMember[member.id] ?? const [],
        paidPeriodIds,
      );

      final paidEnds =
          statusPeriods.where((p) => p.isPaid).map((p) => p.periodEnd);

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

  /// Collapses the member's cycles into one timeline, oldest first.
  ///
  /// Two enrolments can both hold a cycle starting the same month — the old
  /// plan's paid January and the replacement plan's freshly-rolled January.
  /// They are one month of the member's life, and it is paid: a payment
  /// against either one settles it. Without this the unpaid copy could win and
  /// the member would read DUE for a month they had already paid.
  static List<StatusPeriod> _mergeCycles(
    List<MembershipPeriod> periods,
    Set<int> paidPeriodIds,
  ) {
    final byStart = <int, StatusPeriod>{};

    for (final period in periods) {
      final key = period.periodStart.millisecondsSinceEpoch;
      final isPaid = paidPeriodIds.contains(period.id);
      final existing = byStart[key];

      if (existing == null) {
        byStart[key] = StatusPeriod(
          periodStart: period.periodStart,
          periodEnd: period.periodEnd,
          isPaid: isPaid,
        );
        continue;
      }

      // Paid wins, and the longer cycle wins, so a quarterly enrolment is not
      // cut short by a monthly cycle that happens to start the same day.
      byStart[key] = StatusPeriod(
        periodStart: existing.periodStart,
        periodEnd: existing.periodEnd.isAfter(period.periodEnd)
            ? existing.periodEnd
            : period.periodEnd,
        isPaid: existing.isPaid || isPaid,
      );
    }

    return byStart.values.toList()
      ..sort((a, b) => a.periodStart.compareTo(b.periodStart));
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

  /// Everyone already registered on [phone].
  ///
  /// A number is shared far more often by mistake than by family, so the form
  /// shows this list before accepting a second member on it.
  Future<List<Member>> membersOnPhone(String phone, {int? excluding}) async {
    if (phone.isEmpty) return const [];
    final sharing =
        await (db.select(db.members)..where((m) => m.phone.equals(phone))).get();
    return sharing.where((m) => m.id != excluding).toList();
  }

  /// One number can belong to several members — relatives are routinely
  /// registered under a single family phone — so a number on its own no longer
  /// identifies a person. The name is the other half of the key, matched
  /// ignoring case, punctuation and stray spacing.
  Future<Member?> findByPhoneAndName({
    required String phone,
    required String fullName,
  }) async =>
      matchByName(await membersOnPhone(phone), fullName);

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

      final active = await openMembershipFor(db, id);

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
  Future<void> setActive(int id, bool active, {int? actorId}) async {
    final member =
        await (db.select(db.members)..where((m) => m.id.equals(id)))
            .getSingleOrNull();

    await (db.update(db.members)..where((m) => m.id.equals(id))).write(
      MembersCompanion(
        deactivatedAt: Value(active ? null : DateTime.now().toUtc()),
      ),
    );

    if (member == null) return;
    await _audit.record(
      category: AuditCategory.member,
      action: active
          ? AuditAction.memberReactivated
          : AuditAction.memberDeactivated,
      outcome: AuditOutcome.success,
      actorId: actorId,
      memberId: id,
      memberName: member.fullName,
      summary: '${member.fullName} '
          '${active ? 'reactivated' : 'deactivated'}',
    );
  }

  /// Removes a member and everything that exists only to describe them.
  ///
  /// Refused outright while any payment is recorded against them: their money
  /// is the gym's own history, and a delete that quietly rewrote last year's
  /// revenue would be the most damaging thing in this application. That guard
  /// runs inside the transaction, so a payment taken at the same moment on
  /// another screen cannot slip past it.
  ///
  /// Foreign keys are enforced on every connection, so the order below is not a
  /// preference: notes and billing cycles point at the member and their
  /// enrolments, and have to go first.
  Future<MemberDeleteResult> deleteMember({
    required int id,
    int? actorId,
  }) async {
    final member =
        await (db.select(db.members)..where((m) => m.id.equals(id)))
            .getSingleOrNull();
    if (member == null) return const MemberDeleteNotFound();

    final outcome = await db.transaction(() async {
      final payments = await (db.select(db.payments)
            ..where((p) => p.memberId.equals(id)))
          .get();

      if (payments.isNotEmpty) {
        return MemberDeleteRefused(
          memberName: member.fullName,
          paymentCount: payments.length,
        );
      }

      final membershipIds =
          (await (db.select(db.memberships)..where((m) => m.memberId.equals(id)))
                  .get())
              .map((m) => m.id)
              .toList();

      await (db.delete(db.memberNotes)..where((n) => n.memberId.equals(id)))
          .go();

      if (membershipIds.isNotEmpty) {
        await (db.delete(db.membershipPeriods)
              ..where((p) => p.membershipId.isIn(membershipIds)))
            .go();
      }

      await (db.delete(db.memberships)..where((m) => m.memberId.equals(id)))
          .go();
      await (db.delete(db.members)..where((m) => m.id.equals(id))).go();

      return MemberDeleted(member.fullName);
    });

    switch (outcome) {
      case MemberDeleted():
        await _audit.record(
          category: AuditCategory.member,
          action: AuditAction.memberDeleted,
          outcome: AuditOutcome.success,
          actorId: actorId,
          memberId: id,
          memberName: member.fullName,
          summary: '${member.fullName} deleted '
              '(member #${member.memberCode})',
          detail: const [
            'No payments were recorded against this member.',
            'Their notes, plan enrolment and billing cycles were removed.',
          ],
        );
      case MemberDeleteRefused(:final paymentCount):
        await _audit.record(
          category: AuditCategory.member,
          action: AuditAction.memberDeleteRefused,
          outcome: AuditOutcome.refused,
          actorId: actorId,
          memberId: id,
          memberName: member.fullName,
          summary: 'Deletion of ${member.fullName} refused — '
              '$paymentCount payment${paymentCount == 1 ? '' : 's'} recorded',
          detail: const [
            'Payments must be deleted before the member can be.',
          ],
        );
      case MemberDeleteNotFound():
        break;
    }

    return outcome;
  }


  Future<List<MembershipPlan>> plans() => (db.select(db.membershipPlans)
        ..where((p) => p.isActive.equals(true))
        ..orderBy([(p) => OrderingTerm(expression: p.durationMonths)]))
      .get();

  /// The plans offerable to [memberId], which is the active list plus whatever
  /// they are already on.
  ///
  /// A plan the gym has stopped selling can still have members on it. Offering
  /// only active plans left the edit form holding a plan id that was not among
  /// its own options, which Flutter's dropdown rejects outright — so editing
  /// anything about such a member, even their phone number, was impossible.
  Future<List<MembershipPlan>> plansFor(int? memberId) async {
    final active = await plans();
    if (memberId == null) return active;

    final membership = await openMembershipFor(db, memberId);
    if (membership == null) return active;
    if (active.any((p) => p.id == membership.planId)) return active;

    final current = await (db.select(db.membershipPlans)
          ..where((p) => p.id.equals(membership.planId)))
        .getSingleOrNull();
    if (current == null) return active;

    return [...active, current]
      ..sort((a, b) => a.durationMonths.compareTo(b.durationMonths));
  }
}
