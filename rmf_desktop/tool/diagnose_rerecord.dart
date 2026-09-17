import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/import_service.dart';
import 'package:rich_man_fitness/services/ledger_import.dart';
import 'package:rich_man_fitness/services/payment_edit_service.dart';
import 'package:rich_man_fitness/data/audit_repository.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';
import 'package:rich_man_fitness/services/record_payment_service.dart';
import 'package:rich_man_fitness/services/startup_maintenance.dart';
import 'package:rich_man_fitness/services/whatsapp/mock_client.dart';

class _FakeRenderer extends ReceiptRenderer {
  @override
  Future<RenderedReceipt> render(ReceiptData data) async =>
      RenderedReceipt(pdf: await buildPdf(data), png: Uint8List(0));
}

class _FakeStorage extends ReceiptStorage {
  _FakeStorage(this._dir);
  final Directory _dir;

  @override
  Future<Directory> root() async => _dir;
}

/// Walks the exact sequence the gym went through, printing the books at each
/// step. Not an assertion — a way of seeing where the money actually lands.
///
///     fvm flutter test tool/diagnose_rerecord.dart
void main() {
  test('import at 1,500 -> raise to 2,500 -> delete all -> re-record at 2,500',
      () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    addTearDown(db.close);
    await seedDatabase(db);

    final workspace = await Directory.systemTemp.createTemp('rmf-diag');
    addTearDown(() => workspace.delete(recursive: true));

    final members = MemberRepository(db);
    final adminId = (await db.select(db.users).getSingle()).id;
    final payments = RecordPaymentService(
      db: db,
      renderer: _FakeRenderer(),
      storage: _FakeStorage(workspace),
      clientFactory: () async => MockWhatsAppClient(),
    );
    final editor = PaymentEditService(
      db: db,
      renderer: _FakeRenderer(),
      storage: _FakeStorage(workspace),
      audit: AuditRepository(db),
      payments: payments,
    );

    final planId = (await db.into(db.membershipPlans).insertReturning(
              MembershipPlansCompanion.insert(
                name: 'Student',
                durationMonths: 1,
                priceMinor: 150000,
              ),
            ))
        .id;

    // --- 1. Imported from the Excel sheet, Rs. 1,500 a month Jan-Sep --------
    final ledger = ParsedLedger(
      year: 2026,
      mapping: const ColumnMapping(name: 0),
      rows: [
        ParsedMemberRow(
          sourceRow: 2,
          name: 'Abdul Qadir',
          rawPhone: '03254097472',
          normalizedPhone: '+923254097472',
          memberCode: 1,
          reference: null,
          notes: null,
          payments: [
            for (var m = 1; m <= 9; m++)
              ParsedMonthPayment(month: m, amountMinor: 150000),
          ],
          problems: const [],
          warnings: const [],
        ),
      ],
    );

    await ImportService(db).commit(
      ledger: ledger,
      planId: planId,
      recordedById: adminId,
      now: DateTime.utc(2026, 9, 15),
    );

    final memberId = (await db.select(db.members).getSingle()).id;

    Future<void> dump(String label) async {
      final cycles = await periodsForMember(db, memberId);
      final money =
          await collectedByPeriod(db, [for (final c in cycles) c.id]);
      final row = await members.byId(memberId, now: DateTime.utc(2026, 9, 15));
      final pays = await (db.select(db.payments)
            ..where((p) => p.memberId.equals(memberId)))
          .get();

      // ignore: avoid_print
      print('\n=== $label ===');
      for (final c in cycles) {
        // ignore: avoid_print
        print('  ${c.periodStart.toUtc().toIso8601String().substring(0, 10)}'
            ' -> ${c.periodEnd.toUtc().toIso8601String().substring(0, 10)}'
            '  billed ${(c.expectedAmountMinor / 100).toStringAsFixed(0).padLeft(5)}'
            '  got ${((money[c.id] ?? 0) / 100).toStringAsFixed(0).padLeft(5)}'
            '  ${c.settledAt != null ? 'settled' : 'OPEN'}');
      }
      // ignore: avoid_print
      print('  STATUS: ${row!.status}   outstanding: '
          '${row.outstandingMinor == null ? '-' : (row.outstandingMinor! / 100).toStringAsFixed(0)}'
          '   payments: ${pays.length}'
          '   collected: ${(pays.fold(0, (s, p) => s + p.amountMinor) / 100).toStringAsFixed(0)}');
    }

    await dump('1. After the Excel import at Rs. 1,500');

    // --- 2. The owner changes the plan price to Rs. 2,500 ------------------
    await (db.update(db.membershipPlans)..where((p) => p.id.equals(planId)))
        .write(const MembershipPlansCompanion(priceMinor: Value(250000)));
    await runStartupMaintenance(db, now: DateTime.utc(2026, 9, 15));
    await dump('2. After raising the plan to Rs. 2,500 and reloading');

    // --- 3. Delete every payment -------------------------------------------
    for (final p in await (db.select(db.payments)
          ..where((x) => x.memberId.equals(memberId)))
        .get()) {
      await editor.delete(paymentId: p.id, actorId: adminId);
    }
    await runStartupMaintenance(db, now: DateTime.utc(2026, 9, 15));
    await dump('3. After deleting every payment');

    // --- 4. Re-record Rs. 2,500 for each month, on Automatic ---------------
    for (var month = 1; month <= 9; month++) {
      try {
        await payments.recordAdvancePayment(AdvancePaymentInput(
          memberId: memberId,
          amountMinor: 250000,
          method: PaymentMethod.cash,
          paymentDate: DateTime.utc(2026, month, 4),
          sendWhatsApp: false,
          recordedById: adminId,
          idempotencyKey: 'redo-$month',
          confirmedAdvance: true,
        ));
      } catch (error) {
        // ignore: avoid_print
        print('  !! month $month REFUSED: $error');
      }
    }
    await dump('4. After re-recording Rs. 2,500 x9 on AUTOMATIC');
  });
}
