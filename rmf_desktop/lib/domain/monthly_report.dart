import 'package:equatable/equatable.dart';

import '../data/database.dart' show PaymentMethod;
import 'member_status.dart';
import 'payment_method.dart';

const _monthNames = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// One calendar month on the gym's clock — the unit every report is about.
class ReportMonth extends Equatable implements Comparable<ReportMonth> {
  const ReportMonth(this.year, this.month);

  factory ReportMonth.of(DateTime at) => ReportMonth(at.year, at.month);

  final int year;

  /// 1-12.
  final int month;

  /// First instant of the month on the gym's clock. Payments are moments on
  /// that clock, so this is the bound they are counted against.
  DateTime get start => DateTime(year, month, 1);

  /// First instant of the next month — the exclusive end.
  DateTime get end => DateTime(year, month + 1, 1);

  /// The same month as calendar days anchored to UTC midnight, which is how
  /// joining dates and billing cycles are stored. See `domain/dates.dart`.
  DateTime get utcStart => DateTime.utc(year, month, 1);
  DateTime get utcEnd => DateTime.utc(year, month + 1, 1);

  int get daysInMonth => DateTime(year, month + 1, 0).day;

  ReportMonth get previous => ReportMonth.of(DateTime(year, month - 1, 1));
  ReportMonth get next => ReportMonth.of(DateTime(year, month + 1, 1));

  /// "October 2026".
  String get label => '${_monthNames[month - 1]} $year';

  /// "Oct".
  String get shortName => _monthNames[month - 1].substring(0, 3);

  /// "October".
  String get name => _monthNames[month - 1];

  @override
  int compareTo(ReportMonth other) =>
      year != other.year ? year - other.year : month - other.month;

  bool isAfter(ReportMonth other) => compareTo(other) > 0;
  bool isBefore(ReportMonth other) => compareTo(other) < 0;

  @override
  List<Object?> get props => [year, month];

  @override
  String toString() => label;
}

/// What narrows a report. Every field empty is the whole gym.
///
/// Which figures each one touches is part of the definition, and the screen
/// says so beside the filters:
///
/// * [search] and [status] pick members, and through them their payments.
/// * [planId] picks members by the plan they are on, and payments by the plan
///   of the cycle they paid for — a payment made before a plan change counts
///   under the plan it was made on.
/// * [method] is a property of a payment only, so it narrows the money and
///   leaves the member counts alone.
class ReportFilters extends Equatable {
  const ReportFilters({
    this.planId,
    this.method,
    this.status,
    this.search = '',
  });

  final int? planId;
  final PaymentMethod? method;
  final MemberStatus? status;
  final String search;

  bool get isEmpty =>
      planId == null && method == null && status == null && search.trim().isEmpty;

  ReportFilters copyWith({
    int? Function()? planId,
    PaymentMethod? Function()? method,
    MemberStatus? Function()? status,
    String? search,
  }) =>
      ReportFilters(
        planId: planId == null ? this.planId : planId(),
        method: method == null ? this.method : method(),
        status: status == null ? this.status : status(),
        search: search ?? this.search,
      );

  /// The filters in force, as "Plan: Monthly" lines — for the chips on screen
  /// and the line on the PDF, which must read the same.
  List<String> describe(Map<int, String> planNames) => [
        if (search.trim().isNotEmpty) 'Search: “${search.trim()}”',
        if (planId != null) 'Plan: ${planNames[planId] ?? 'Unknown plan'}',
        if (method != null) 'Method: ${paymentMethodLabel(method!)}',
        if (status != null) 'Status: ${memberStatusName(status!)}',
      ];

  @override
  List<Object?> get props => [planId, method, status, search.trim()];
}

/// A value axis that reads in round steps — 0, 5k, 10k … 25k rather than
/// 0, 6.3k, 12.5k — topping out at or just above [peak].
({int top, int step, int ticks}) niceAxis(int peak, {int targetTicks = 4}) {
  if (peak <= 0) return (top: 100, step: 25, ticks: 4);
  final rough = peak / targetTicks;
  var magnitude = 1;
  while (magnitude * 10 <= rough) {
    magnitude *= 10;
  }
  final step = [1, 2, 2.5, 5, 10]
      .map((m) => (magnitude * m).round())
      .firstWhere((s) => s >= rough);
  final ticks = (peak / step).ceil();
  return (top: step * ticks, step: step, ticks: ticks);
}

/// "Paid", where the badge says "PAID".
String memberStatusName(MemberStatus status) => switch (status) {
      MemberStatus.paid => 'Paid',
      MemberStatus.due => 'Due',
      MemberStatus.expired => 'Expired',
      MemberStatus.inactive => 'Inactive',
    };

/// "+12%" / "−4%" from a comparison, or null where a percentage would mislead:
/// nothing to compare with, or growth from zero.
String? percentChange(Compared figure) {
  final previous = figure.previous;
  if (previous == null || previous == 0) return null;
  final pct = (figure.value - previous) / previous * 100;
  final rounded = pct.abs() >= 10 ? pct.round().toString() : pct.toStringAsFixed(1);
  if (rounded == '0' || rounded == '0.0') return '0%';
  return pct > 0 ? '+$rounded%' : '−${rounded.replaceFirst('-', '')}%';
}

/// A figure and the one it is compared against, when a comparison is honest.
class Compared extends Equatable {
  const Compared(this.value, {this.previous});

  final int value;

  /// Null when there is nothing fair to compare with — the month before the
  /// gym's records begin.
  final int? previous;

  int? get change => previous == null ? null : value - previous!;

  @override
  List<Object?> get props => [value, previous];
}

/// One payment as the report lists it.
class ReportPayment {
  const ReportPayment({
    required this.paymentId,
    required this.paidAt,
    required this.memberId,
    required this.memberCode,
    required this.memberName,
    required this.planName,
    required this.amountMinor,
    required this.method,
    required this.imported,
    this.reference,
    this.receiptNumber,
  });

  final int paymentId;

  /// On the gym's clock. For an [imported] payment only the month is real.
  final DateTime paidAt;
  final int memberId;
  final int memberCode;
  final String memberName;

  /// The plan of the cycle the money went to; null for a payment that was
  /// never tied to one.
  final String? planName;
  final int amountMinor;
  final PaymentMethod method;

  /// Carried in from the owner's Excel ledger, which records the month and
  /// not the day.
  final bool imported;
  final String? reference;
  final String? receiptNumber;
}

/// One member as the report's membership table lists them.
class ReportMember {
  const ReportMember({
    required this.memberId,
    required this.memberCode,
    required this.name,
    required this.planName,
    required this.joiningDate,
    required this.enrolmentStart,
    required this.paidUntil,
    required this.status,
    required this.isNew,
    required this.paidThisMonthMinor,
    required this.arrearsMinor,
  });

  final int memberId;
  final int memberCode;
  final String name;
  final String? planName;

  /// UTC midnight, a calendar day.
  final DateTime joiningDate;

  /// When the member's current enrolment began, UTC midnight.
  final DateTime? enrolmentStart;

  /// Exclusive end of the last paid cycle, UTC midnight.
  final DateTime? paidUntil;

  /// At the report's snapshot moment.
  final MemberStatus status;

  /// Joined during the reported month.
  final bool isNew;

  /// What the member paid during the month, under the report's filters.
  final int paidThisMonthMinor;

  /// Unpaid on cycles begun by the snapshot moment.
  final int arrearsMinor;

  /// Paid during the month having joined before it — a renewal.
  bool get renewed => !isNew && paidThisMonthMinor > 0;
}

/// One month of [MembershipGrowth].
class GrowthPoint {
  const GrowthPoint({
    required this.month,
    required this.newMembers,
    required this.renewals,
  });

  final ReportMonth month;
  final int newMembers;
  final int renewals;
}

/// One bar of a revenue breakdown.
class BreakdownSlice {
  const BreakdownSlice({
    required this.label,
    required this.amountMinor,
    required this.count,
  });

  final String label;
  final int amountMinor;
  final int count;
}

/// Everything the Reports screen and the PDF show for one month, worked out
/// once.
///
/// Both read this one object, so an exported figure cannot disagree with the
/// one on screen: there is no second calculation for it to come from.
class MonthlyReport {
  const MonthlyReport({
    required this.month,
    required this.filters,
    required this.generatedAt,
    required this.snapshotAt,
    required this.isCurrentMonth,
    required this.comparisonLabel,
    required this.revenue,
    required this.paymentCount,
    required this.importedRevenueMinor,
    required this.collectedToDateMinor,
    required this.payingMembers,
    required this.owed,
    required this.owingMembers,
    required this.totalMembers,
    required this.activeMembers,
    required this.newMembers,
    required this.renewals,
    required this.expiredMembers,
    required this.statusCounts,
    required this.dailyRevenueMinor,
    required this.daysElapsed,
    required this.previousDailyRevenueMinor,
    required this.growth,
    required this.byMethod,
    required this.byPlan,
    required this.payments,
    required this.members,
  });

  final ReportMonth month;
  final ReportFilters filters;
  final DateTime generatedAt;

  /// The moment the member counts and statuses describe: now for the month in
  /// progress, the month's last moment for one that has ended.
  final DateTime snapshotAt;

  /// The month is still running, so its figures are so far, not final.
  final bool isCurrentMonth;

  /// What the comparisons are against — "September", or "1–2 September" while
  /// this month is under way, so a part month is never set against a whole.
  final String? comparisonLabel;

  // --- Money in the month --------------------------------------------------

  final Compared revenue;
  final Compared paymentCount;

  /// The part of [revenue] carried in from the Excel ledger, which has no day
  /// and so is not on the daily chart.
  final int importedRevenueMinor;

  /// Every payment from the first one on record to the end of this month.
  final int collectedToDateMinor;

  /// Distinct members who paid in the month.
  final int payingMembers;

  /// Unpaid on cycles begun by [snapshotAt], across members not inactive.
  final Compared owed;
  final int owingMembers;

  int? get averagePerPayingMemberMinor =>
      payingMembers == 0 ? null : (revenue.value / payingMembers).round();

  // --- Members -------------------------------------------------------------

  /// On the roster at [snapshotAt], inactive members included.
  final Compared totalMembers;

  /// Not deactivated at [snapshotAt].
  final Compared activeMembers;
  final Compared newMembers;
  final Compared renewals;
  final Compared expiredMembers;
  final Map<MemberStatus, int> statusCounts;

  // --- Charts --------------------------------------------------------------

  /// One entry per day of the month, app-recorded payments only.
  final List<int> dailyRevenueMinor;

  /// How many of [dailyRevenueMinor]'s days have happened: today's date while
  /// the month runs, so the line stops at today instead of falling to zero
  /// across days still to come.
  final int daysElapsed;

  /// The same for the month before, for the comparison line; null when that
  /// month precedes every record.
  final List<int>? previousDailyRevenueMinor;

  /// Up to twelve months ending with this one, from the first month on record.
  final List<GrowthPoint> growth;

  /// Largest first.
  final List<BreakdownSlice> byMethod;
  final List<BreakdownSlice> byPlan;

  // --- Detail --------------------------------------------------------------

  /// Newest first.
  final List<ReportPayment> payments;

  /// By member code.
  final List<ReportMember> members;

  bool get hasPayments => payments.isNotEmpty;
}
