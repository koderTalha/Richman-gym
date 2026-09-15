import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/membership_queries.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/billing_maintenance.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';
import 'package:rich_man_fitness/services/record_payment_service.dart';
import 'package:rich_man_fitness/services/whatsapp/mock_client.dart';

import '../test/support/treadmill_fixture.dart';

/// Writes a real SQLite file holding the gym's reported state, so the repair
/// can be rehearsed in the actual app before it is done on the owner's PC.
///
///     fvm flutter test tool/make_treadmill_db.dart
///
/// Writes to `build/treadmill-demo.sqlite` unless OUT names somewhere else:
///
///     OUT=/tmp/demo.sqlite fvm flutter test tool/make_treadmill_db.dart
///
/// INSTALL=1 puts it straight where the macOS app reads its database, moving
/// any existing one aside first, so `flutter run -d macos` opens it directly:
///
///     INSTALL=1 fvm flutter test tool/make_treadmill_db.dart
///
/// Close the app before doing that — SQLite locks the file while it runs, and
/// the -wal and -shm files beside it have to go with the database or the app
/// reads a mix of the two. Otherwise load it through Settings -> Backup &
/// Restore, which validates the file and swaps it in on the next launch.
/// Log in as admin@richmanfitness.local / RichMan#2026.
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

void main() {
  test('writes a database reproducing the fee-rise treadmill', () async {
    // Where the sandboxed macOS build keeps its database.
    final live = File('${Platform.environment['HOME']}/Library/Containers/'
        'com.richmanfitness.richManFitness/Data/Documents/'
        'richmanfitness.sqlite');

    final installing = Platform.environment['INSTALL'] == '1';
    final out = File(Platform.environment['OUT'] ??
        (installing ? live.path : 'build/treadmill-demo.sqlite'));
    await out.parent.create(recursive: true);

    // Move the existing database aside rather than deleting it: this is the
    // developer's own gym data, and "reproduce the bug" must never be the
    // thing that loses it.
    if (await out.exists()) {
      final stamp = DateTime.now()
          .toIso8601String()
          .replaceAll(':', '-')
          .split('.')
          .first;
      final kept = '${out.path}.before-$stamp';
      await out.rename(kept);
      // ignore: avoid_print
      print('Existing database moved to $kept');
    }
    // The write-ahead log belongs to the database that just moved; leaving it
    // behind would have the app reading half of each.
    for (final suffix in ['-wal', '-shm']) {
      final sidecar = File('${out.path}$suffix');
      if (await sidecar.exists()) await sidecar.delete();
    }

    final db = AppDatabase.forTesting(NativeDatabase(out));
    addTearDown(db.close);
    await seedDatabase(db);

    final workspace = await Directory.systemTemp.createTemp('rmf-demo');
    addTearDown(() => workspace.delete(recursive: true));

    final members = MemberRepository(db);
    final cycles = BillingCycleService(db);
    final adminId = (await db.select(db.users).getSingle()).id;
    final payments = RecordPaymentService(
      db: db,
      renderer: _FakeRenderer(),
      storage: _FakeStorage(workspace),
      clientFactory: () async => MockWhatsAppClient(),
    );

    final planId = (await db.into(db.membershipPlans).insertReturning(
              MembershipPlansCompanion.insert(
                name: 'Student',
                description: const Value('The plan whose price was raised.'),
                durationMonths: 1,
                priceMinor: treadmillOldFee,
              ),
            ))
        .id;

    // The member on the treadmill: Rs. 2,500 paid in full every month, shown
    // "Overdue since 01 Sep 2026 - Rs. 1,500".
    final stuck = await buildTreadmilledMember(
      db: db,
      members: members,
      payments: payments,
      adminId: adminId,
      planId: planId,
    );

    // A second member on the same plan who joined after the price rise, so
    // there is a healthy member on screen to compare against.
    final healthy = await members.create(
      fullName: 'Bilal Ahmed',
      phone: '+923254097473',
      planId: planId,
      joiningDate: DateTime.utc(2026, 6, 1),
    );
    for (final on in [
      DateTime.utc(2026, 6, 4),
      DateTime.utc(2026, 7, 4),
      DateTime.utc(2026, 8, 4),
      DateTime.utc(2026, 9, 4),
    ]) {
      await BillingMaintenance(db).ensureCurrentPeriods(now: on);
      await payments.recordAdvancePayment(AdvancePaymentInput(
        memberId: healthy,
        amountMinor: treadmillNewFee,
        method: PaymentMethod.cash,
        paymentDate: on,
        sendWhatsApp: false,
        recordedById: adminId,
        idempotencyKey: 'healthy-${on.month}',
      ));
    }

    // --- Prove the file really is the reported state ------------------------
    final at = DateTime.utc(2026, 9, 15);
    final stuckRow = await members.byId(stuck, now: at);
    final owing = (await cycles.forMember(stuck))!.nextUnsettled!;

    expect(stuckRow!.outstandingMinor, 150000);
    expect(owing.start, DateTime.utc(2026, 9, 1));
    expect(owing.collectedMinor, 100000);
    expect((await members.byId(healthy, now: at))!.outstandingMinor, null);

    // ignore: avoid_print
    print('''

Wrote ${out.absolute.path}
${installing ? '  Installed where the macOS app reads it — just launch the app.' : '  Load it via Settings -> Backup & Restore -> Restore, or re-run with INSTALL=1.'}
  Sign in:  admin@richmanfitness.local / RichMan#2026
  Plan:     Student, Rs. 2,500 (was Rs. 1,500 until April)

  Abdul Qadir  - ON THE TREADMILL
${(await periodsForMember(db, stuck)).map((p) {
      final got = p.settledAt != null ? 'settled' : 'OPEN';
      return '    ${p.periodStart.toUtc().toIso8601String().substring(0, 10)}'
          '  billed Rs. ${(p.expectedAmountMinor / 100).toStringAsFixed(0)}'
          '  $got';
    }).join('\n')}
    Shows: DUE, Rs. 1,500 overdue since 01 Sep 2026
    Truth: September was billed Rs. 2,500 and already holds Rs. 1,000

  Bilal Ahmed  - healthy, joined after the rise
''');
  });
}
