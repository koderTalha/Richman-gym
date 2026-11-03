import 'package:drift/drift.dart';

import '../domain/member_status.dart';
import '../domain/monthly_report.dart';
import '../domain/payment_method.dart';
import '../domain/phone.dart';
import 'database.dart';
import 'listing_search.dart';
import 'member_repository.dart';
import 'membership_queries.dart';

/// Builds the Reports screen's [MonthlyReport] — and with it the PDF, which
/// prints the same object.
///
/// Every figure comes from rows already in the database through the rules the
/// rest of the app uses: money is `payments` (every row is money collected —
/// the app has no pending, refunded or cancelled payment), and membership
/// status is [MemberRepository]'s, rewound to the month's end by
/// [MemberRepository.listAsOf] so a past month reads as it stood then.
///
/// The work is done in memory over one read of each table. The gym's whole
/// history is a few thousand payments, which loads in milliseconds on the
/// counter PC, and filtering in Dart keeps every figure on one predicate
/// rather than a dozen SQL statements that could each drift from the others.
class ReportRepository {
  ReportRepository(
    this.db, {
    MemberRepository? members,
    DateTime Function()? clock,
  })  : _members = members ?? MemberRepository(db),
        _clock = clock ?? DateTime.now;

  final AppDatabase db;
  final MemberRepository _members;

  /// Injectable so "the month in progress" can be tested on a fixed day.
  final DateTime Function() _clock;

  ReportMonth get currentMonth => ReportMonth.of(_clock());

  /// Every plan, retired ones included: a past month's payments can belong to
  /// a plan the gym no longer sells.
  Future<List<MembershipPlan>> plans() => (db.select(db.membershipPlans)
        ..orderBy([(p) => OrderingTerm(expression: p.name)]))
      .get();

  /// The earliest month anything happened in — a member joining or a payment
  /// — or null for an empty database. Nothing before it is reportable, and
  /// comparing against a month before it would compare against nothing.
  Future<ReportMonth?> firstMonthOnRecord() async {
    final firstJoin = db.members.joiningDate.min();
    final firstPayment = db.payments.paymentDate.min();
    final joined = (await (db.selectOnly(db.members)..addColumns([firstJoin]))
            .getSingle())
        .read(firstJoin);
    final paid =
        (await (db.selectOnly(db.payments)..addColumns([firstPayment]))
                .getSingle())
            .read(firstPayment);

    final months = [
      if (joined != null) ReportMonth.of(joined.toUtc()),
      if (paid != null) ReportMonth.of(paid.toLocal()),
    ];
    if (months.isEmpty) return null;
    return months.reduce((a, b) => a.isBefore(b) ? a : b);
  }

  Future<MonthlyReport> build(
    ReportMonth month, {
    ReportFilters filters = const ReportFilters(),
  }) async {
    final now = _clock();
    final isCurrent = month == ReportMonth.of(now);
    final snapshotAt = isCurrent ? now : _lastMomentOf(month);

    final first = await firstMonthOnRecord();
    final hasPrevious = first != null && !month.previous.isBefore(first);

    final roster = await _members.listAsOf(snapshotAt);
    final previousRoster = hasPrevious
        ? await _members.listAsOf(_lastMomentOf(month.previous))
        : null;

    final membersById = {
      for (final m in await db.select(db.members).get()) m.id: m,
    };
    final plansById = {for (final p in await plans()) p.id: p};

    // Everything up to the end of the month: the month itself, its
    // comparison, the growth chart's year and the running total.
    final payments = await (db.select(db.payments)
          ..where((p) => p.paymentDate.isSmallerThanValue(month.end))
          ..orderBy([
            (p) => OrderingTerm(
                expression: p.paymentDate, mode: OrderingMode.desc),
            (p) => OrderingTerm(expression: p.id, mode: OrderingMode.desc),
          ]))
        .get();

    final planOfPayment = await _planIdsOf(payments);

    final term = filters.search.trim();
    final receiptHits = term.isEmpty ? const <int>{} : await _receiptHits(term);

    final statusOf = {for (final r in roster) r.id: r.status};

    bool memberMatches(Member member) =>
        term.isEmpty || _matchesSearch(member, term);

    bool memberPasses(MemberRow row) =>
        memberMatches(row.member) &&
        (filters.status == null || row.status == filters.status) &&
        (filters.planId == null || row.membership?.planId == filters.planId);

    bool paymentPasses(Payment payment) {
      if (filters.method != null && payment.method != filters.method) {
        return false;
      }
      if (filters.planId != null &&
          planOfPayment[payment.id] != filters.planId) {
        return false;
      }
      if (filters.status != null &&
          statusOf[payment.memberId] != filters.status) {
        return false;
      }
      if (term.isEmpty) return true;
      final member = membersById[payment.memberId];
      return receiptHits.contains(payment.id) ||
          (member != null && memberMatches(member));
    }

    final matching = payments.where(paymentPasses).toList();
    final members = roster.where(memberPasses).toList();

    // --- Money ---------------------------------------------------------------

    List<Payment> within(DateTime from, DateTime to) => [
          for (final p in matching)
            if (!p.paymentDate.isBefore(from) && p.paymentDate.isBefore(to)) p,
        ];

    final monthPayments = within(month.start, month.end);
    int sum(Iterable<Payment> rows) =>
        rows.fold(0, (total, p) => total + p.amountMinor);

    // While the month is running, it is compared with the same stretch of
    // the month before — the 1st to today — not with a whole month it has
    // not had time to equal.
    final prev = month.previous;
    final comparableEnd = isCurrent ? _sameMomentIn(prev, now) : prev.end;
    final comparableDays = isCurrent
        ? (now.day > prev.daysInMonth ? prev.daysInMonth : now.day)
        : prev.daysInMonth;
    final previousPayments =
        hasPrevious ? within(prev.start, comparableEnd) : const <Payment>[];

    final dailyRevenue = List<int>.filled(month.daysInMonth, 0);
    for (final p in monthPayments) {
      if (p.source == PaymentSource.imported) continue;
      dailyRevenue[p.paymentDate.toLocal().day - 1] += p.amountMinor;
    }

    List<int>? previousDaily;
    if (hasPrevious) {
      previousDaily = List<int>.filled(prev.daysInMonth, 0);
      for (final p in within(prev.start, prev.end)) {
        if (p.source == PaymentSource.imported) continue;
        previousDaily[p.paymentDate.toLocal().day - 1] += p.amountMinor;
      }
    }

    // --- Members -------------------------------------------------------------

    bool joinedIn(Member m, ReportMonth of, {int? byDay}) {
      final joined = m.joiningDate.toUtc();
      if (joined.isBefore(of.utcStart) || !joined.isBefore(of.utcEnd)) {
        return false;
      }
      return byDay == null || joined.day <= byDay;
    }

    // Who renewed in a window: members who paid in it having joined before
    // the month began. Counted once each however many payments they made.
    Set<int> renewersIn(List<Payment> rows, ReportMonth of) => {
          for (final p in rows)
            if (membersById[p.memberId] case final m?
                when m.joiningDate.toUtc().isBefore(of.utcStart))
              p.memberId,
        };

    final memberIds = {for (final m in members) m.id};
    final newThisMonth = {
      for (final m in members)
        if (joinedIn(m.member, month)) m.id,
    };

    final paidByMember = <int, int>{};
    for (final p in monthPayments) {
      paidByMember[p.memberId] = (paidByMember[p.memberId] ?? 0) + p.amountMinor;
    }

    // Who passes the member filters is decided against this month's roster,
    // so the comparison counts the same people's joining a month earlier.
    int newIn(ReportMonth of, {int? byDay}) => members
        .where((m) => joinedIn(m.member, of, byDay: byDay))
        .length;

    int renewalsIn(List<Payment> rows, ReportMonth of) =>
        renewersIn(rows, of).where(memberIds.contains).length;

    final previousMembers =
        previousRoster?.where(memberPasses).toList(growable: false);

    int? previousCount(bool Function(MemberRow) test) =>
        previousMembers?.where(test).length;

    int arrearsOf(Iterable<MemberRow> rows) => rows
        .where((r) => r.status != MemberStatus.inactive)
        .fold(0, (total, r) => total + r.arrearsMinor);

    final statusCounts = {
      for (final status in MemberStatus.values)
        status: members.where((m) => m.status == status).length,
    };

    // --- Growth ---------------------------------------------------------------

    final growth = <GrowthPoint>[];
    var cursor = month;
    for (var i = 0; i < 12; i++) {
      if (first == null || cursor.isBefore(first)) break;
      final rows = within(cursor.start, cursor.end);
      growth.insert(
        0,
        GrowthPoint(
          month: cursor,
          newMembers: newIn(cursor),
          renewals: renewalsIn(rows, cursor),
        ),
      );
      cursor = cursor.previous;
    }

    // --- Breakdowns -------------------------------------------------------------

    List<BreakdownSlice> breakdown(String Function(Payment) keyOf) {
      final amounts = <String, int>{};
      final counts = <String, int>{};
      for (final p in monthPayments) {
        final key = keyOf(p);
        amounts[key] = (amounts[key] ?? 0) + p.amountMinor;
        counts[key] = (counts[key] ?? 0) + 1;
      }
      return [
        for (final key in amounts.keys)
          BreakdownSlice(
            label: key,
            amountMinor: amounts[key]!,
            count: counts[key]!,
          ),
      ]..sort((a, b) => b.amountMinor.compareTo(a.amountMinor));
    }

    String planName(int? planId) =>
        planId == null ? 'No plan' : (plansById[planId]?.name ?? 'No plan');

    // --- Detail ------------------------------------------------------------------

    final receiptNumbers = await _receiptNumbersFor(
        monthPayments.map((p) => p.id).toList());

    final reportPayments = [
      for (final p in monthPayments)
        ReportPayment(
          paymentId: p.id,
          paidAt: p.paymentDate.toLocal(),
          memberId: p.memberId,
          memberCode: membersById[p.memberId]?.memberCode ?? 0,
          memberName: membersById[p.memberId]?.fullName ?? 'Deleted member',
          planName: planOfPayment[p.id] == null
              ? null
              : plansById[planOfPayment[p.id]]?.name,
          amountMinor: p.amountMinor,
          method: p.method,
          imported: p.source == PaymentSource.imported,
          reference: p.referenceNumber,
          receiptNumber: receiptNumbers[p.id],
        ),
    ];

    final reportMembers = [
      for (final m in members)
        ReportMember(
          memberId: m.id,
          memberCode: m.member.memberCode,
          name: m.member.fullName,
          planName: m.plan?.name,
          joiningDate: m.member.joiningDate.toUtc(),
          enrolmentStart: m.membership?.startDate.toUtc(),
          paidUntil: m.paidUntil?.toUtc(),
          status: m.status,
          isNew: newThisMonth.contains(m.id),
          paidThisMonthMinor: paidByMember[m.id] ?? 0,
          arrearsMinor:
              m.status == MemberStatus.inactive ? 0 : m.arrearsMinor,
        ),
    ];

    final comparableDay = isCurrent ? comparableDays : null;

    return MonthlyReport(
      month: month,
      filters: filters,
      generatedAt: now,
      snapshotAt: snapshotAt,
      isCurrentMonth: isCurrent,
      comparisonLabel: !hasPrevious
          ? null
          : isCurrent && comparableDays < prev.daysInMonth
              ? '1–$comparableDays ${prev.name}'
              : prev.label,
      revenue: Compared(
        sum(monthPayments),
        previous: hasPrevious ? sum(previousPayments) : null,
      ),
      paymentCount: Compared(
        monthPayments.length,
        previous: hasPrevious ? previousPayments.length : null,
      ),
      importedRevenueMinor: sum(
          monthPayments.where((p) => p.source == PaymentSource.imported)),
      collectedToDateMinor: sum(matching),
      payingMembers: monthPayments.map((p) => p.memberId).toSet().length,
      owed: Compared(
        arrearsOf(members),
        previous: previousMembers == null ? null : arrearsOf(previousMembers),
      ),
      owingMembers: members
          .where((m) => m.status != MemberStatus.inactive && m.arrearsMinor > 0)
          .length,
      totalMembers: Compared(members.length, previous: previousMembers?.length),
      activeMembers: Compared(
        members.where((m) => m.status != MemberStatus.inactive).length,
        previous: previousCount((m) => m.status != MemberStatus.inactive),
      ),
      newMembers: Compared(
        newThisMonth.length,
        previous: hasPrevious ? newIn(prev, byDay: comparableDay) : null,
      ),
      renewals: Compared(
        renewalsIn(monthPayments, month),
        previous: hasPrevious ? renewalsIn(previousPayments, prev) : null,
      ),
      expiredMembers: Compared(
        statusCounts[MemberStatus.expired]!,
        previous: previousCount((m) => m.status == MemberStatus.expired),
      ),
      statusCounts: statusCounts,
      dailyRevenueMinor: dailyRevenue,
      daysElapsed: isCurrent ? now.day : month.daysInMonth,
      previousDailyRevenueMinor: previousDaily,
      growth: growth,
      byMethod: breakdown((p) => paymentMethodLabel(p.method)),
      byPlan: breakdown((p) => planName(planOfPayment[p.id])),
      payments: reportPayments,
      members: reportMembers,
    );
  }

  /// The last moment of [month] that is inside it on both clocks the data
  /// keeps: the gym's, which payments are dated on, and UTC midnights, which
  /// joining dates and cycles are. East of Greenwich, as Pakistan is, that is
  /// the gym's 23:59:59.999 on the last day.
  static DateTime _lastMomentOf(ReportMonth month) {
    const tick = Duration(milliseconds: 1);
    final local = month.end.subtract(tick);
    final utc = month.utcEnd.subtract(tick);
    return local.isBefore(utc) ? local : utc;
  }

  /// [at]'s day and time of day, moved into [month] — clamped to its end for
  /// the 31st against a 30-day month.
  static DateTime _sameMomentIn(ReportMonth month, DateTime at) {
    final moved = DateTime(month.year, month.month, at.day, at.hour, at.minute,
        at.second, at.millisecond);
    return moved.isAfter(month.end) ? month.end : moved;
  }

  /// The plan each payment's money went to: the plan of the enrolment its
  /// cycle was billed under. Absent for a payment tied to no cycle.
  Future<Map<int, int>> _planIdsOf(List<Payment> payments) async {
    final periodIds = payments
        .map((p) => p.membershipPeriodId)
        .whereType<int>()
        .toSet()
        .toList();
    final membershipOfPeriod = <int, int>{};
    for (final chunk in idChunks(periodIds)) {
      final rows = await (db.selectOnly(db.membershipPeriods)
            ..addColumns(
                [db.membershipPeriods.id, db.membershipPeriods.membershipId])
            ..where(db.membershipPeriods.id.isIn(chunk)))
          .get();
      for (final row in rows) {
        membershipOfPeriod[row.read(db.membershipPeriods.id)!] =
            row.read(db.membershipPeriods.membershipId)!;
      }
    }
    final planOfMembership = {
      for (final m in await db.select(db.memberships).get()) m.id: m.planId,
    };
    return {
      for (final p in payments)
        p.id: ?planOfMembership[membershipOfPeriod[p.membershipPeriodId]],
    };
  }

  /// Payments whose receipt number contains [term], as the Payments screen's
  /// search finds them.
  Future<Set<int>> _receiptHits(String term) async {
    final rows = await (db.selectOnly(db.receipts)
          ..addColumns([db.receipts.paymentId])
          ..where(db.receipts.receiptNumber
              .lower()
              .like(containsPattern(term), escapeChar: r'\')))
        .get();
    return {for (final row in rows) row.read(db.receipts.paymentId)!};
  }

  Future<Map<int, String>> _receiptNumbersFor(List<int> paymentIds) async {
    final numbers = <int, String>{};
    for (final chunk in idChunks(paymentIds)) {
      final rows = await (db.select(db.receipts)
            ..where((r) => r.paymentId.isIn(chunk)))
          .get();
      for (final r in rows) {
        numbers[r.paymentId] = r.receiptNumber;
      }
    }
    return numbers;
  }

  /// The member search the rest of the app does in SQL (`memberMatches` in
  /// listing_search.dart), on a member already in memory: name, phone as
  /// stored or as people type it, or member code.
  static bool _matchesSearch(Member member, String term) {
    final lower = term.toLowerCase();
    if (member.fullName.toLowerCase().contains(lower)) return true;
    if (member.phone.contains(term)) return true;
    if (int.tryParse(term) == member.memberCode) return true;
    final normalized = normalizePhone(term);
    if (normalized != null && member.phone == normalized) return true;
    if (_phoneShaped.hasMatch(term)) {
      final digits = phoneSearchDigits(term);
      if (digits.isNotEmpty && member.phone.contains(digits)) return true;
    }
    return false;
  }

  static final _phoneShaped = RegExp(r'^[\d\s+\-().]+$');
}
