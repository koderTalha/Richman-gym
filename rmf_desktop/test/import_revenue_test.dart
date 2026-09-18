import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/payment_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';

/// Whether money carried in from the owner's ledger counts as takings.
///
/// It does. The columns in their sheet hold real figures — Excel only draws
/// "###" when the column is too narrow for the number, and the workbook still
/// stores it — so an imported month is money the gym genuinely collected and
/// belongs in that month's revenue.
///
/// What the ledger does *not* know is the day. It has one column per month, so
/// every imported payment is dated to the first of the month it covers, which
/// is a placeholder rather than the day the member actually handed the money
/// over. So it counts towards a month, where the attribution is real, and not
/// towards a day, where it would credit whichever date the placeholder happens
/// to fall on.
void main() {
  late AppDatabase db;
  late PaymentRepository payments;
  late int memberId;
  late int adminId;

  setUp(() async {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    await seedDatabase(db);
    payments = PaymentRepository(db);
    adminId = (await db.select(db.users).getSingle()).id;

    final planId = (await (db.select(db.membershipPlans)
              ..where((p) => p.name.equals('Monthly')))
            .getSingle())
        .id;

    memberId = await MemberRepository(db).create(
      fullName: 'Ali Khan',
      phone: '+923000000001',
      planId: planId,
      joiningDate: DateTime.utc(2026, 1, 1),
    );
  });

  tearDown(() async => db.close());

  Future<void> record({
    required int amountMinor,
    required DateTime on,
    required PaymentSource source,
    required String key,
  }) async {
    await db.into(db.payments).insert(
          PaymentsCompanion.insert(
            memberId: memberId,
            amountMinor: amountMinor,
            method: PaymentMethod.cash,
            paymentDate: on,
            source: Value(source),
            recordedById: adminId,
            idempotencyKey: key,
          ),
        );
  }

  final septemberStart = DateTime.utc(2026, 9, 1);
  final octoberStart = DateTime.utc(2026, 10, 1);

  group('a month’s revenue', () {
    test('counts money imported for that month', () async {
      await record(
        amountMinor: 1000000,
        on: DateTime.utc(2026, 9, 1),
        source: PaymentSource.imported,
        key: 'import-2026-1-9',
      );

      expect(await payments.totalMinorBetween(septemberStart, octoberStart),
          1000000);
    });

    test('adds imported and app-recorded money together', () async {
      await record(
        amountMinor: 1000000,
        on: DateTime.utc(2026, 9, 1),
        source: PaymentSource.imported,
        key: 'import-2026-1-9',
      );
      await record(
        amountMinor: 300000,
        on: DateTime.utc(2026, 9, 12),
        source: PaymentSource.manual,
        key: 'manual-1',
      );

      expect(await payments.totalMinorBetween(septemberStart, octoberStart),
          1300000);
    });

    test('leaves another month’s imported money where it belongs', () async {
      await record(
        amountMinor: 1000000,
        on: DateTime.utc(2026, 1, 1),
        source: PaymentSource.imported,
        key: 'import-2026-1-1',
      );

      expect(
          await payments.totalMinorBetween(septemberStart, octoberStart), 0);
      expect(
        await payments.totalMinorBetween(
            DateTime.utc(2026, 1, 1), DateTime.utc(2026, 2, 1)),
        1000000,
      );
    });
  });

  group('a day’s revenue', () {
    final firstOfMonth = DateTime.utc(2026, 9, 1);
    final secondOfMonth = DateTime.utc(2026, 9, 2);

    test('leaves out imported money, whose day is only a placeholder',
        () async {
      await record(
        amountMinor: 1000000,
        on: firstOfMonth,
        source: PaymentSource.imported,
        key: 'import-2026-1-9',
      );

      expect(
        await payments.totalMinorBetween(firstOfMonth, secondOfMonth,
            includeImported: false),
        0,
      );
    });

    test('still counts money taken in the app that day', () async {
      await record(
        amountMinor: 300000,
        on: firstOfMonth,
        source: PaymentSource.manual,
        key: 'manual-1',
      );

      expect(
        await payments.totalMinorBetween(firstOfMonth, secondOfMonth,
            includeImported: false),
        300000,
      );
    });

    test('counts only the app’s payments', () async {
      await record(
        amountMinor: 1000000,
        on: firstOfMonth,
        source: PaymentSource.imported,
        key: 'import-2026-1-9',
      );
      await record(
        amountMinor: 300000,
        on: firstOfMonth,
        source: PaymentSource.manual,
        key: 'manual-1',
      );

      expect(
        await payments.countBetween(firstOfMonth, secondOfMonth,
            includeImported: false),
        1,
      );
    });
  });
}
