import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/report_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/domain/monthly_report.dart';
import 'package:rich_man_fitness/services/report_pdf.dart';

/// The exported report: that it builds, breaks long tables across pages, and
/// survives the months with nothing in them.
void main() {
  late AppDatabase db;
  late int adminId;

  final today = DateTime(2026, 10, 15, 12);
  const october = ReportMonth(2026, 10);

  ReportFonts fonts() {
    ByteData font(String weight) => ByteData.sublistView(
        File('assets/fonts/Inter-$weight.ttf').readAsBytesSync());
    return ReportFonts(
      regular: font('Regular'),
      medium: font('Medium'),
      bold: font('Bold'),
    );
  }

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    adminId = (await db.select(db.users).getSingle()).id;
  });

  tearDown(() async => db.close());

  Future<void> members(int count) async {
    final planId = (await db.select(db.membershipPlans).get()).first.id;
    for (var i = 1; i <= count; i++) {
      final id = await db.into(db.members).insert(MembersCompanion.insert(
            memberCode: i,
            fullName: 'Test Member $i',
            phone: '+92300${i.toString().padLeft(7, '0')}',
            joiningDate: DateTime.utc(2026, i.isEven ? 3 : 10, 1 + i % 14),
          ));
      final membership =
          await db.into(db.memberships).insert(MembershipsCompanion.insert(
                memberId: id,
                planId: planId,
                startDate: DateTime.utc(2026, 3, 1),
              ));
      final period = await db
          .into(db.membershipPeriods)
          .insert(MembershipPeriodsCompanion.insert(
            membershipId: membership,
            periodStart: DateTime.utc(2026, 10, 1),
            periodEnd: DateTime.utc(2026, 11, 1),
            expectedAmountMinor: 300000,
          ));
      if (i % 3 != 0) {
        await db.into(db.payments).insert(PaymentsCompanion.insert(
              memberId: id,
              membershipPeriodId: Value(period),
              amountMinor: 300000,
              method: i.isOdd ? PaymentMethod.cash : PaymentMethod.easypaisa,
              paymentDate: DateTime(2026, 10, 1 + i % 14, 10),
              recordedById: adminId,
              idempotencyKey: 'k$i',
            ));
      }
    }
  }

  /// Pages in the finished file. The page tree is written uncompressed, so
  /// each page is one "/Type /Page" dictionary.
  int pageCount(Uint8List pdf) => RegExp(r'/Type\s*/Page(?![s])')
      .allMatches(latin1.decode(pdf, allowInvalid: true))
      .length;

  Future<Uint8List> render(MonthlyReport report) => buildReportPdf(
        ReportPdfInput(
          report: report,
          gymName: 'Test Gym',
          gymPhone: '0300-0000000',
          brand: const Color(0xFFE11D2E),
          planNames: const {},
        ),
        fonts(),
      );

  test('a busy month runs its payment table over several pages', () async {
    await members(150);
    final report =
        await ReportRepository(db, clock: () => today).build(october);
    expect(report.payments, hasLength(100));

    final pdf = await render(report);

    expect(latin1.decode(pdf.sublist(0, 5)), '%PDF-');
    expect(pageCount(pdf), greaterThanOrEqualTo(4),
        reason: 'summary, charts, and a hundred payment rows besides');
  });

  test('an empty month still makes a readable document', () async {
    final report =
        await ReportRepository(db, clock: () => today).build(october);

    final pdf = await render(report);
    expect(latin1.decode(pdf.sublist(0, 5)), '%PDF-');
    expect(pageCount(pdf), 3, reason: 'one page each, none left blank');
  });

  test('a filtered report says so', () async {
    await members(6);
    final report = await ReportRepository(db, clock: () => today).build(
        october,
        filters: const ReportFilters(method: PaymentMethod.easypaisa));
    expect(report.filters.describe(const {}), ['Method: Easypaisa']);
    expect(await render(report), isNotEmpty);
  });

  test('the file is named for the month', () {
    expect(reportFileName(october), 'Gym_Report_October_2026.pdf');
  });
}
