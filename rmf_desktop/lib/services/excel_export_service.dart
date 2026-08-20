import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:excel/excel.dart' show Excel, TextCellValue, IntCellValue;

import '../data/database.dart';
import '../domain/billing_period.dart';
import '../domain/member_status.dart';
import '../domain/money.dart';

/// Exports everything to a workbook the owner can open without this app.
///
/// This matters more than a database snapshot for the person actually running
/// the gym: they came from Excel, and a file they can read on any computer is
/// the backup they will trust. One sheet deliberately reproduces their original
/// ledger layout, so the data goes back out in the shape it came in.
class ExcelExportService {
  ExcelExportService(this.db);

  final AppDatabase db;

  static const _monthLabels = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  Future<Uint8List> build({DateTime? now}) async {
    final at = now ?? DateTime.now();
    final excel = Excel.createExcel();

    final settings =
        await (db.select(db.gymSettings)..where((s) => s.id.equals(1)))
            .getSingleOrNull();
    final currency = settings?.currency ?? defaultCurrency;

    final members = await db.select(db.members).get();
    final plans = {
      for (final p in await db.select(db.membershipPlans).get()) p.id: p
    };
    final memberships = await db.select(db.memberships).get();
    final periods = await db.select(db.membershipPeriods).get();
    final payments = await db.select(db.payments).get();
    final receipts = {
      for (final r in await db.select(db.receipts).get()) r.paymentId: r
    };
    final users = {for (final u in await db.select(db.users).get()) u.id: u};

    _writeMembers(
      excel,
      members: members,
      plans: plans,
      memberships: memberships,
      periods: periods,
      payments: payments,
      currency: currency,
      now: at,
    );

    _writePayments(
      excel,
      members: members,
      payments: payments,
      periods: periods,
      memberships: memberships,
      plans: plans,
      receipts: receipts,
      users: users,
      currency: currency,
    );

    _writeLedgerSheets(
      excel,
      members: members,
      memberships: memberships,
      periods: periods,
      payments: payments,
    );

    _writePlans(excel, plans.values.toList(), currency);

    // createExcel() seeds an empty default sheet we never wrote to.
    excel.delete('Sheet1');

    final bytes = excel.encode();
    if (bytes == null) {
      throw StateError('The workbook could not be encoded.');
    }
    return Uint8List.fromList(bytes);
  }

  void _writeMembers(
    Excel excel, {
    required List<Member> members,
    required Map<int, MembershipPlan> plans,
    required List<Membership> memberships,
    required List<MembershipPeriod> periods,
    required List<Payment> payments,
    required String currency,
    required DateTime now,
  }) {
    final sheet = excel['Members'];
    sheet.appendRow([
      TextCellValue('Enroll.'),
      TextCellValue('Name'),
      TextCellValue('Contact Detail'),
      TextCellValue('Gender'),
      TextCellValue('Membership'),
      TextCellValue('Fee'),
      TextCellValue('Joining Date'),
      TextCellValue('Paid Until'),
      TextCellValue('Status'),
    ]);

    final paidPeriodIds =
        payments.map((p) => p.membershipPeriodId).whereType<int>().toSet();
    final openByMember = _openMembershipByMember(memberships);
    final periodsByMember = _periodsByMember(memberships, periods);

    for (final member in _sorted(members)) {
      final membership = openByMember[member.id];
      final plan = membership == null ? null : plans[membership.planId];

      // Every enrolment's cycles, not just the open one: a member whose plan
      // changed keeps the months they paid under the previous enrolment, and
      // reading only the open one reported them as never having paid at all.
      final memberPeriods = periodsByMember[member.id] ?? const [];

      final status = deriveMemberStatus(
        deactivatedAt: member.deactivatedAt,
        periods: memberPeriods
            .map((p) => StatusPeriod(
                  periodStart: p.periodStart,
                  periodEnd: p.periodEnd,
                  isPaid: paidPeriodIds.contains(p.id),
                ))
            .toList(),
        now: now.toUtc(),
      );

      final paidEnds = memberPeriods
          .where((p) => paidPeriodIds.contains(p.id))
          .map((p) => p.periodEnd);

      final feeMinor = membership == null
          ? null
          : (membership.feeOverrideMinor ?? plan?.priceMinor);

      sheet.appendRow([
        IntCellValue(member.memberCode),
        TextCellValue(member.fullName),
        // The original sheet uses "-" for a member with no number on file.
        TextCellValue(member.phone.isEmpty ? '-' : member.phone),
        TextCellValue(member.gender ?? ''),
        TextCellValue(plan?.name ?? ''),
        TextCellValue(
            feeMinor == null ? '' : formatMinorUnits(feeMinor, currency)),
        TextCellValue(_date(member.joiningDate)),
        TextCellValue(paidEnds.isEmpty
            ? '-'
            : _date(paidEnds.reduce((a, b) => a.isAfter(b) ? a : b))),
        TextCellValue(status.label),
      ]);
    }
  }

  void _writePayments(
    Excel excel, {
    required List<Member> members,
    required List<Payment> payments,
    required List<MembershipPeriod> periods,
    required List<Membership> memberships,
    required Map<int, MembershipPlan> plans,
    required Map<int, Receipt> receipts,
    required Map<int, User> users,
    required String currency,
  }) {
    final sheet = excel['Payments'];
    sheet.appendRow([
      TextCellValue('Receipt No'),
      TextCellValue('Enroll.'),
      TextCellValue('Member'),
      TextCellValue('Contact Detail'),
      TextCellValue('Billing Period'),
      TextCellValue('Amount'),
      TextCellValue('Method'),
      TextCellValue('Reference'),
      TextCellValue('Payment Date'),
      TextCellValue('Recorded By'),
    ]);

    final byMember = {for (final m in members) m.id: m};
    final periodById = {for (final p in periods) p.id: p};
    final membershipById = {for (final m in memberships) m.id: m};

    final ordered = [...payments]
      ..sort((a, b) => b.paymentDate.compareTo(a.paymentDate));

    for (final payment in ordered) {
      final member = byMember[payment.memberId];
      final period = periodById[payment.membershipPeriodId];
      final membership =
          period == null ? null : membershipById[period.membershipId];
      final duration = plans[membership?.planId]?.durationMonths ?? 1;

      sheet.appendRow([
        TextCellValue(receipts[payment.id]?.receiptNumber ?? ''),
        IntCellValue(member?.memberCode ?? 0),
        TextCellValue(member?.fullName ?? ''),
        TextCellValue((member?.phone.isEmpty ?? true) ? '-' : member!.phone),
        TextCellValue(period == null
            ? ''
            : formatBillingPeriod(period.periodStart.toUtc(), duration)),
        TextCellValue(formatMinorUnits(payment.amountMinor, currency)),
        TextCellValue(_methodLabel(payment.method)),
        TextCellValue(payment.referenceNumber ?? ''),
        TextCellValue(_recordedDate(payment.paymentDate)),
        TextCellValue(users[payment.recordedById]?.name ?? ''),
      ]);
    }
  }

  /// One sheet per year, in the owner's original wide layout: a row per member
  /// with a column per month. This is the format the ledger already used, so it
  /// reads exactly like the sheet they have been keeping by hand.
  void _writeLedgerSheets(
    Excel excel, {
    required List<Member> members,
    required List<Membership> memberships,
    required List<MembershipPeriod> periods,
    required List<Payment> payments,
  }) {
    final years = periods.map((p) => p.periodStart.toUtc().year).toSet().toList()
      ..sort();
    if (years.isEmpty) return;

    final paymentByPeriod = <int, Payment>{
      for (final payment in payments)
        if (payment.membershipPeriodId != null)
          payment.membershipPeriodId!: payment,
    };

    final periodsByMember = _periodsByMember(memberships, periods);
    final sortedMembers = _sorted(members);

    for (final year in years) {
      final sheet = excel['Ledger $year'];
      sheet.appendRow([
        TextCellValue('Enroll.'),
        TextCellValue('Name'),
        TextCellValue('Contact Detail'),
        ..._monthLabels.map(TextCellValue.new),
        TextCellValue('Total'),
      ]);

      for (final member in sortedMembers) {
        // Every member appears, exactly as in the original ledger where someone
        // with no payments still occupies a row of dashes. Skipping them would
        // quietly drop people from the export.
        final cells = List<TextCellValue>.generate(
            12, (_) => TextCellValue('-'));
        var totalMinor = 0;

        for (final period in periodsByMember[member.id] ?? const []) {
          if (period.periodStart.toUtc().year != year) continue;
          final payment = paymentByPeriod[period.id];
          if (payment == null) continue;

          final month = period.periodStart.toUtc().month;
          cells[month - 1] = TextCellValue(_amount(payment.amountMinor));
          totalMinor += payment.amountMinor;
        }

        sheet.appendRow([
          IntCellValue(member.memberCode),
          TextCellValue(member.fullName),
          TextCellValue(member.phone.isEmpty ? '-' : member.phone),
          ...cells,
          TextCellValue(totalMinor == 0 ? '-' : _amount(totalMinor)),
        ]);
      }
    }
  }

  void _writePlans(
      Excel excel, List<MembershipPlan> plans, String currency) {
    final sheet = excel['Plans'];
    sheet.appendRow([
      TextCellValue('Plan'),
      TextCellValue('Duration (months)'),
      TextCellValue('Price'),
      TextCellValue('Active'),
    ]);

    for (final plan in plans) {
      sheet.appendRow([
        TextCellValue(plan.name),
        IntCellValue(plan.durationMonths),
        TextCellValue(formatMinorUnits(plan.priceMinor, currency)),
        TextCellValue(plan.isActive ? 'Yes' : 'No'),
      ]);
    }
  }

  List<Member> _sorted(List<Member> members) =>
      [...members]..sort((a, b) => a.memberCode.compareTo(b.memberCode));

  /// Indexed once instead of scanned per member.
  ///
  /// These sheets used to search the full membership and period lists inside
  /// the per-member loop, and the ledger sheets did it again per year — work
  /// that grows with the square of the gym's history, on the interface thread,
  /// every time a backup is taken.
  static Map<int, Membership> _openMembershipByMember(
      List<Membership> memberships) {
    final open = <int, Membership>{};
    for (final membership in memberships) {
      if (membership.endDate == null) open[membership.memberId] = membership;
    }
    return open;
  }

  static Map<int, List<MembershipPeriod>> _periodsByMember(
    List<Membership> memberships,
    List<MembershipPeriod> periods,
  ) {
    final memberByMembership = {
      for (final m in memberships) m.id: m.memberId,
    };

    final byMember = <int, List<MembershipPeriod>>{};
    for (final period in periods) {
      final memberId = memberByMembership[period.membershipId];
      if (memberId == null) continue;
      byMember.putIfAbsent(memberId, () => []).add(period);
    }
    return byMember;
  }

  /// Whole rupees render as "3000", not "3000.0" — the ledger the owner knows
  /// has no decimal point in it.
  static String _amount(int minor) {
    final major = fromMinorUnits(minor);
    return major == major.roundToDouble()
        ? major.toStringAsFixed(0)
        : major.toStringAsFixed(2);
  }

  /// For dates the app anchors to UTC midnight on purpose — cycle boundaries,
  /// joining dates — so they read as the calendar day they were stored as
  /// wherever the machine's clock is set.
  static String _date(DateTime value) => _format(value.toUtc());

  /// For a real moment in time, such as when a payment was taken. Rendered in
  /// the gym's own timezone: a payment the owner dated the 1st has to appear on
  /// the 1st, not on the 31st of the month before.
  static String _recordedDate(DateTime value) => _format(value.toLocal());

  static String _format(DateTime at) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(at.day)}-${_monthLabels[at.month - 1]}-${at.year % 100}';
  }

  /// Deliberately not `paymentMethodLabel`: the workbook follows the wording
  /// of the ledger the owner has always kept, which is not the wording the app
  /// screens use.
  static String _methodLabel(PaymentMethod method) => switch (method) {
        PaymentMethod.cash => 'Cash Payment',
        PaymentMethod.bankTransfer => 'Bank Transfer',
        PaymentMethod.easypaisa => 'Easypaisa',
        PaymentMethod.jazzcash => 'JazzCash',
        PaymentMethod.card => 'Card',
        PaymentMethod.other => 'Online Payment',
      };
}
