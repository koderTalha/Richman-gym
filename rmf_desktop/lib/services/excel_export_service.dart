import 'dart:typed_data';

import 'package:drift/drift.dart';
import 'package:excel/excel.dart' show Excel, TextCellValue, IntCellValue;

import '../data/database.dart';
import '../data/member_repository.dart';
import '../data/payment_cycles.dart';
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
    // The Members screen's own rows, so the export's PAID/DUE and Paid Until
    // are the app's answer and not a second one worked out here. The export
    // used to read `payments.membership_period_id`, which names only the
    // first cycle a payment touched and knows nothing of `settled_at`: every
    // freshly imported member covered by a free cycle, and every member who
    // paid ahead, read DUE in the file while the app said PAID.
    final memberRows = await MemberRepository(db).list(now: at);
    final plans = {
      for (final p in await db.select(db.membershipPlans).get()) p.id: p
    };
    final memberships = await db.select(db.memberships).get();
    final periods = await db.select(db.membershipPeriods).get();
    final payments = await db.select(db.payments).get();
    final allocations = await db.select(db.paymentAllocations).get();
    final receipts = {
      for (final r in await db.select(db.receipts).get()) r.paymentId: r
    };
    final users = {for (final u in await db.select(db.users).get()) u.id: u};

    _writeMembers(excel, rows: memberRows, currency: currency);

    // Which cycles each payment paid for, from its allocations — the same
    // rule the payment history and Receipts screens label by. Worked out
    // from the tables already in memory rather than queried per payment.
    final periodIdsByPayment = periodIdsPaidBy(payments, allocations);

    _writePayments(
      excel,
      members: members,
      payments: payments,
      paidCycles: paidCyclesFrom(
        periodIdsByPayment: periodIdsByPayment,
        periods: periods,
        memberships: memberships,
        plans: plans.values,
      ),
      receipts: receipts,
      users: users,
      currency: currency,
    );

    _writeLedgerSheets(
      excel,
      members: members,
      plans: plans,
      memberships: memberships,
      periods: periods,
      collectedByPeriod: _collectedByPeriod(
        payments: payments,
        allocations: allocations,
        periodIdsByPayment: periodIdsByPayment,
        periods: periods,
      ),
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
    required List<MemberRow> rows,
    required String currency,
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

    // Already in enrolment-number order, and already reading every enrolment's
    // cycles rather than only the open one's — a member whose plan changed
    // keeps the months they paid under the previous enrolment.
    for (final row in rows) {
      final member = row.member;
      final feeMinor = row.feeMinor;
      final paidUntil = row.paidUntil;

      sheet.appendRow([
        IntCellValue(member.memberCode),
        TextCellValue(member.fullName),
        // The original sheet uses "-" for a member with no number on file.
        TextCellValue(member.phone.isEmpty ? '-' : member.phone),
        TextCellValue(member.gender ?? ''),
        TextCellValue(row.plan?.name ?? ''),
        TextCellValue(
            feeMinor == null ? '' : formatMinorUnits(feeMinor, currency)),
        TextCellValue(_date(member.joiningDate)),
        TextCellValue(paidUntil == null ? '-' : _date(paidUntil)),
        TextCellValue(row.status.label),
      ]);
    }
  }

  void _writePayments(
    Excel excel, {
    required List<Member> members,
    required List<Payment> payments,
    required Map<int, List<PaidCycle>> paidCycles,
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

    final ordered = [...payments]
      ..sort((a, b) => b.paymentDate.compareTo(a.paymentDate));

    for (final payment in ordered) {
      final member = byMember[payment.memberId];
      // Every month the payment paid for, as the Receipts screen names it:
      // three months taken at once read "January 2026 - March 2026", not
      // just the first month.
      final cycles = paidCycles[payment.id];

      sheet.appendRow([
        TextCellValue(receipts[payment.id]?.receiptNumber ?? ''),
        IntCellValue(member?.memberCode ?? 0),
        TextCellValue(member?.fullName ?? ''),
        TextCellValue((member?.phone.isEmpty ?? true) ? '-' : member!.phone),
        TextCellValue(
            cycles == null ? '' : (formatPaidCycles(cycles) ?? '')),
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
    required Map<int, MembershipPlan> plans,
    required List<Membership> memberships,
    required List<MembershipPeriod> periods,
    required Map<int, int> collectedByPeriod,
  }) {
    final years = periods.map((p) => p.periodStart.toUtc().year).toSet().toList()
      ..sort();
    if (years.isEmpty) return;

    final periodsByMember = _periodsByMember(memberships, periods);
    final openByMember = _openMembershipByMember(memberships);
    final sortedMembers = _sorted(members);

    for (final year in years) {
      final sheet = excel['Ledger $year'];
      sheet.appendRow([
        TextCellValue('Enroll.'),
        TextCellValue('Name'),
        TextCellValue('Contact Detail'),
        ..._monthLabels.map(TextCellValue.new),
        TextCellValue('Total'),
        // Named, not numbered: the importer resolves this back to the plan of
        // that name, so a ledger exported here can be read in again without the
        // whole roster landing on whichever plan the wizard happened to offer.
        TextCellValue('Plan'),
      ]);

      for (final member in sortedMembers) {
        // Every member appears, exactly as in the original ledger where someone
        // with no payments still occupies a row of dashes. Skipping them would
        // quietly drop people from the export.
        //
        // Each month's cell is everything collected for the cycle starting in
        // it — every part-payment, and each month's share of money paid
        // ahead — not one payment per cycle. Keeping only the last payment
        // dropped the first of two part-payments from the file the owner
        // treats as their backup. Summed rather than overwritten, too, for the
        // rare month two enrolments both hold a cycle in.
        final monthMinor = List<int>.filled(12, 0);

        for (final period in periodsByMember[member.id] ?? const []) {
          if (period.periodStart.toUtc().year != year) continue;
          final collected = collectedByPeriod[period.id] ?? 0;
          if (collected == 0) continue;
          monthMinor[period.periodStart.toUtc().month - 1] += collected;
        }

        final cells = [
          for (final minor in monthMinor)
            TextCellValue(minor == 0 ? '-' : _amount(minor)),
        ];
        final totalMinor = monthMinor.fold(0, (sum, m) => sum + m);

        final membership = openByMember[member.id];
        final planName =
            membership == null ? null : plans[membership.planId]?.name;

        sheet.appendRow([
          IntCellValue(member.memberCode),
          TextCellValue(member.fullName),
          TextCellValue(member.phone.isEmpty ? '-' : member.phone),
          ...cells,
          TextCellValue(totalMinor == 0 ? '-' : _amount(totalMinor)),
          TextCellValue(planName ?? '-'),
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

  /// The money collected for each cycle: the sum of its allocations.
  ///
  /// A payment with no allocation rows at all — one predating them, or a raw
  /// row — counts in full against its `membershipPeriodId`, as it always did.
  /// And should a payment's allocations add up to less than the payment, the
  /// remainder is put on the first cycle it paid for rather than left out:
  /// the ledger's totals must account for every rupee taken against a cycle.
  /// Money recorded against no cycle at all has no month to sit under and
  /// appears on the Payments sheet only.
  static Map<int, int> _collectedByPeriod({
    required List<Payment> payments,
    required List<PaymentAllocation> allocations,
    required Map<int, Set<int>> periodIdsByPayment,
    required List<MembershipPeriod> periods,
  }) {
    final collected = <int, int>{};
    final allocatedByPayment = <int, int>{};
    for (final allocation in allocations) {
      collected.update(allocation.membershipPeriodId,
          (sum) => sum + allocation.amountMinor,
          ifAbsent: () => allocation.amountMinor);
      allocatedByPayment.update(
          allocation.paymentId, (sum) => sum + allocation.amountMinor,
          ifAbsent: () => allocation.amountMinor);
    }

    final startById = {for (final p in periods) p.id: p.periodStart};
    for (final payment in payments) {
      final remainder =
          payment.amountMinor - (allocatedByPayment[payment.id] ?? 0);
      if (remainder <= 0) continue;

      // The earliest cycle the payment paid for: its own first cycle.
      final ids = (periodIdsByPayment[payment.id] ?? const <int>{})
          .where(startById.containsKey)
          .toList()
        ..sort((a, b) => startById[a]!.compareTo(startById[b]!));
      if (ids.isEmpty) continue;

      collected.update(ids.first, (sum) => sum + remainder,
          ifAbsent: () => remainder);
    }
    return collected;
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
