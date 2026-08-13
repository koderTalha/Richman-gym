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

    for (final member in _sorted(members)) {
      final membership = memberships.firstWhereOrNull(
          (m) => m.memberId == member.id && m.endDate == null);
      final plan = membership == null ? null : plans[membership.planId];

      final memberPeriods =
          periods.where((p) => p.membershipId == membership?.id).toList();

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

    final ordered = [...payments]
      ..sort((a, b) => b.paymentDate.compareTo(a.paymentDate));

    for (final payment in ordered) {
      final member = byMember[payment.memberId];
      final period =
          periods.firstWhereOrNull((p) => p.id == payment.membershipPeriodId);
      final membership = period == null
          ? null
          : memberships.firstWhereOrNull((m) => m.id == period.membershipId);
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
        TextCellValue(_date(payment.paymentDate)),
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

    for (final year in years) {
      final sheet = excel['Ledger $year'];
      sheet.appendRow([
        TextCellValue('Enroll.'),
        TextCellValue('Name'),
        TextCellValue('Contact Detail'),
        ..._monthLabels.map(TextCellValue.new),
        TextCellValue('Total'),
      ]);

      for (final member in _sorted(members)) {
        // Every member appears, exactly as in the original ledger where someone
        // with no payments still occupies a row of dashes. Skipping them would
        // quietly drop people from the export.
        final membership = memberships.firstWhereOrNull(
            (m) => m.memberId == member.id && m.endDate == null);

        final cells = List<TextCellValue>.generate(
            12, (_) => TextCellValue('-'));
        var totalMinor = 0;

        for (final period in periods.where((p) =>
            membership != null &&
            p.membershipId == membership.id &&
            p.periodStart.toUtc().year == year)) {
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

  /// Whole rupees render as "3000", not "3000.0" — the ledger the owner knows
  /// has no decimal point in it.
  static String _amount(int minor) {
    final major = fromMinorUnits(minor);
    return major == major.roundToDouble()
        ? major.toStringAsFixed(0)
        : major.toStringAsFixed(2);
  }

  static String _date(DateTime value) {
    final at = value.toUtc();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(at.day)}-${_monthLabels[at.month - 1]}-${at.year % 100}';
  }

  static String _methodLabel(PaymentMethod method) => switch (method) {
        PaymentMethod.cash => 'Cash Payment',
        PaymentMethod.bankTransfer => 'Bank Transfer',
        PaymentMethod.easypaisa => 'Easypaisa',
        PaymentMethod.jazzcash => 'JazzCash',
        PaymentMethod.card => 'Card',
        PaymentMethod.other => 'Online Payment',
      };
}

extension _FirstWhereOrNull<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final item in this) {
      if (test(item)) return item;
    }
    return null;
  }
}
