import 'billing_period.dart';
import 'money.dart';

/// The billing-month rules, as one place both recording and editing a payment
/// ask the same questions.
///
/// Everything here is pure: the caller gathers the facts from the database and
/// this decides what, if anything, is wrong with them. That split is what makes
/// the rules testable without a database, and what stops the same rule being
/// written twice — once in the Record Payment dialog and once in Edit Payment.

enum BillingMonthIssue {
  /// The cycle starts before the member ever joined.
  beforeJoining,

  /// Earlier cycles are still unpaid, which usually means the wrong month was
  /// picked rather than that the owner means to skip them.
  unpaidEarlierCycles,

  /// Further ahead than paying one cycle in advance.
  farFuture,

  /// The cycle already has money against it.
  duplicatePayment,
}

/// Whether a finding stops the operation or only asks the owner to look again.
enum FindingSeverity {
  /// Always wrong. Shown as a validation error on the field; there is no
  /// "continue anyway".
  block,

  /// Legitimate but unusual. Shown once, with the owner able to proceed.
  confirm,
}

class BillingMonthFinding {
  const BillingMonthFinding({
    required this.issue,
    required this.severity,
    required this.message,
  });

  final BillingMonthIssue issue;
  final FindingSeverity severity;

  /// Written for the gym owner, not for a developer.
  final String message;
}

/// The result of checking one billing month.
class BillingMonthReview {
  const BillingMonthReview(this.findings);

  const BillingMonthReview.clean() : findings = const [];

  final List<BillingMonthFinding> findings;

  List<BillingMonthFinding> get blocking =>
      findings.where((f) => f.severity == FindingSeverity.block).toList();

  List<BillingMonthFinding> get confirmations =>
      findings.where((f) => f.severity == FindingSeverity.confirm).toList();

  bool get isBlocked => blocking.isNotEmpty;

  /// True only when nothing blocks and something needs a second look, so a
  /// blocked month never also raises a confirmation dialog behind the error.
  bool get needsConfirmation => !isBlocked && confirmations.isNotEmpty;

  bool get isClean => findings.isEmpty;

  /// Every issue found, for the audit trail. Order is stable so a logged
  /// reason reads the same way twice.
  List<BillingMonthIssue> get issues => findings.map((f) => f.issue).toList();
}

/// A billing cycle with no payment recorded against it.
class UnpaidCycle {
  const UnpaidCycle({required this.periodStart, required this.durationMonths});

  final DateTime periodStart;

  /// Carried per cycle rather than assumed: a member who changed plan has
  /// cycles of different lengths in their own history.
  final int durationMonths;

  String get label => formatBillingPeriod(periodStart, durationMonths);
}

/// Money already recorded against the selected cycle.
class ExistingCyclePayment {
  const ExistingCyclePayment({
    required this.amountMinor,
    required this.paymentDate,
  });

  final int amountMinor;
  final DateTime paymentDate;
}

/// Everything the rules need, read from the database by the caller.
class BillingMonthFacts {
  const BillingMonthFacts({
    required this.memberName,
    required this.cycleStart,
    required this.durationMonths,
    required this.joiningDate,
    required this.today,
    this.unpaidEarlierCycles = const [],
    this.existingPayment,
    this.currency = defaultCurrency,
  });

  final String memberName;

  /// UTC start of the cycle being billed.
  ///
  /// Not simply the month the owner picked: on a three-month plan, picking
  /// September means billing the August-October cycle, and every rule and
  /// message here is about that cycle rather than about September. The caller
  /// resolves which cycle a month belongs to and passes its start.
  final DateTime cycleStart;

  /// Length of the plan the cycle belongs to.
  final int durationMonths;

  final DateTime joiningDate;

  /// Now, on the gym's own clock. Passed in so the rules stay pure and the
  /// tests do not depend on the day they run.
  final DateTime today;

  final List<UnpaidCycle> unpaidEarlierCycles;

  /// Null when the cycle is unpaid. When editing, the payment being edited is
  /// excluded by the caller so it cannot be its own duplicate.
  final ExistingCyclePayment? existingPayment;

  final String currency;
}

/// At most this many unpaid cycles are named before the message summarises.
const _namedUnpaidCycles = 3;

BillingMonthReview reviewBillingMonth(BillingMonthFacts facts) {
  final findings = <BillingMonthFinding>[];

  final selected = facts.cycleStart.toUtc();
  final joinedMonth = _monthStart(facts.joiningDate.toUtc());

  // --- Before joining: always wrong, so it blocks --------------------------
  if (selected.isBefore(joinedMonth)) {
    findings.add(BillingMonthFinding(
      issue: BillingMonthIssue.beforeJoining,
      severity: FindingSeverity.block,
      message: '${facts.memberName} joined in '
          '${formatBillingPeriod(joinedMonth, 1)}, so '
          '${formatBillingPeriod(selected, facts.durationMonths)} '
          'is before their membership started.',
    ));
  }

  // --- Earlier cycles left unpaid ------------------------------------------
  final unpaid = facts.unpaidEarlierCycles
      .where((c) => c.periodStart.toUtc().isBefore(selected))
      .toList()
    ..sort((a, b) => a.periodStart.compareTo(b.periodStart));

  if (unpaid.isNotEmpty) {
    findings.add(BillingMonthFinding(
      issue: BillingMonthIssue.unpaidEarlierCycles,
      severity: FindingSeverity.confirm,
      message: _unpaidMessage(unpaid),
    ));
  }

  // --- Further ahead than one cycle in advance -----------------------------
  // Read on the wall clock: which month it is *now* is a question about the
  // gym's own calendar, matching currentBillingMonth().
  final thisMonth = DateTime.utc(facts.today.year, facts.today.month, 1);
  final furthestExpected = DateTime.utc(
    thisMonth.year,
    thisMonth.month + facts.durationMonths,
    1,
  );

  if (selected.isAfter(furthestExpected)) {
    findings.add(BillingMonthFinding(
      issue: BillingMonthIssue.farFuture,
      severity: FindingSeverity.confirm,
      message:
          '${formatBillingPeriod(selected, facts.durationMonths)} is more than '
          'one billing cycle ahead of '
          '${formatBillingPeriod(thisMonth, 1)}.',
    ));
  }

  // --- Already paid --------------------------------------------------------
  final existing = facts.existingPayment;
  if (existing != null) {
    findings.add(BillingMonthFinding(
      issue: BillingMonthIssue.duplicatePayment,
      severity: FindingSeverity.confirm,
      message: 'A payment of '
          '${formatMinorUnits(existing.amountMinor, facts.currency)} is '
          'already recorded for '
          '${formatBillingPeriod(selected, facts.durationMonths)}.',
    ));
  }

  return BillingMonthReview(findings);
}

String _unpaidMessage(List<UnpaidCycle> unpaid) {
  final named = unpaid.take(_namedUnpaidCycles).map((c) => c.label).toList();
  final remaining = unpaid.length - named.length;

  final list = switch (named.length) {
    1 => named.first,
    _ => '${named.take(named.length - 1).join(', ')} and ${named.last}',
  };

  final verb = unpaid.length == 1 ? 'is' : 'are';
  final tail = remaining == 0
      ? ''
      : ' (and $remaining earlier ${remaining == 1 ? 'cycle' : 'cycles'})';

  return '$list$tail $verb still unpaid.';
}

DateTime _monthStart(DateTime at) => DateTime.utc(at.year, at.month, 1);
