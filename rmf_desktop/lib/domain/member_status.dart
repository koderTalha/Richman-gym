/// Membership status is always derived from real dates and payment records —
/// never read from an editable status column. Keeping this a pure function makes
/// the rules testable without a database.
enum MemberStatus { paid, due, expired, inactive }

extension MemberStatusLabel on MemberStatus {
  String get label => switch (this) {
        MemberStatus.paid => 'PAID',
        MemberStatus.due => 'DUE',
        MemberStatus.expired => 'EXPIRED',
        MemberStatus.inactive => 'INACTIVE',
      };
}

/// One billing cycle, reduced to just what the status rules need.
class StatusPeriod {
  const StatusPeriod({
    required this.periodStart,
    required this.periodEnd,
    required this.isPaid,
  });

  final DateTime periodStart;

  /// Exclusive: a cycle ending 2026-09-01 covers up to and including 31 Aug.
  final DateTime periodEnd;

  final bool isPaid;
}

MemberStatus deriveMemberStatus({
  required DateTime? deactivatedAt,
  required List<StatusPeriod> periods,
  DateTime? now,
}) {
  if (deactivatedAt != null) return MemberStatus.inactive;
  if (periods.isEmpty) return MemberStatus.due;

  final at = now ?? DateTime.now().toUtc();

  for (final period in periods) {
    final covers = !period.periodStart.isAfter(at) && at.isBefore(period.periodEnd);
    if (covers) {
      return period.isPaid ? MemberStatus.paid : MemberStatus.due;
    }
  }

  // No cycle covers today. If every cycle is in the past the membership lapsed;
  // if only future cycles exist, nothing is owed for today yet.
  final latestEnd = periods
      .map((p) => p.periodEnd)
      .reduce((a, b) => a.isAfter(b) ? a : b);

  return latestEnd.isAfter(at) ? MemberStatus.due : MemberStatus.expired;
}
