// Timings for the operations the counter PC runs all day, on generated data
// of several sizes. Not part of the normal suite — it lives outside test/ and
// takes minutes — run it on purpose:
//
//     flutter test benchmark/perf_benchmark_test.dart \
//         --dart-define=PERF_LABEL=before --dart-define=PERF_OUT=/some/dir
//
// Every database here is generated; nothing reads or writes the gym's own
// file. The seeded databases are cached in PERF_OUT and copied fresh for each
// size, so two labelled runs measure the same rows.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:rich_man_fitness/bloc/dashboard_bloc.dart';
import 'package:rich_man_fitness/data/database.dart';
import 'package:rich_man_fitness/data/member_repository.dart';
import 'package:rich_man_fitness/data/payment_repository.dart';
import 'package:rich_man_fitness/data/receipt_repository.dart';
import 'package:rich_man_fitness/data/report_repository.dart';
import 'package:rich_man_fitness/data/seed.dart';
import 'package:rich_man_fitness/domain/monthly_report.dart';
import 'package:rich_man_fitness/services/billing_cycle_service.dart';
import 'package:rich_man_fitness/services/receipt_renderer.dart';
import 'package:rich_man_fitness/services/receipt_storage.dart';
import 'package:rich_man_fitness/services/record_payment_service.dart';
import 'package:rich_man_fitness/services/reminder_service.dart';
import 'package:rich_man_fitness/services/startup_maintenance.dart';
import 'package:rich_man_fitness/services/whatsapp/mock_client.dart';

const _label = String.fromEnvironment('PERF_LABEL', defaultValue: 'run');
const _out = String.fromEnvironment('PERF_OUT');
const _sizes = String.fromEnvironment('PERF_SIZES', defaultValue: '600,2000,10000');

/// "Today" for every generated roster and every measured call.
final _now = DateTime(2026, 11, 2, 12);

/// Counts the statements a call sends, so "queries per screen" is a number
/// rather than a guess.
class _Counter extends QueryInterceptor {
  int statements = 0;

  @override
  Future<List<Map<String, Object?>>> runSelect(
      QueryExecutor executor, String statement, List<Object?> args) {
    statements++;
    return super.runSelect(executor, statement, args);
  }

  @override
  Future<int> runInsert(
      QueryExecutor executor, String statement, List<Object?> args) {
    statements++;
    return super.runInsert(executor, statement, args);
  }

  @override
  Future<int> runUpdate(
      QueryExecutor executor, String statement, List<Object?> args) {
    statements++;
    return super.runUpdate(executor, statement, args);
  }

  @override
  Future<int> runDelete(
      QueryExecutor executor, String statement, List<Object?> args) {
    statements++;
    return super.runDelete(executor, statement, args);
  }

  @override
  Future<void> runCustom(
      QueryExecutor executor, String statement, List<Object?> args) {
    statements++;
    return super.runCustom(executor, statement, args);
  }
}

class _FakeRenderer extends ReceiptRenderer {
  @override
  Future<RenderedReceipt> render(ReceiptData data) async =>
      RenderedReceipt(pdf: Uint8List(0), png: Uint8List.fromList([1, 2, 3]));
}

class _FakeStorage extends ReceiptStorage {
  _FakeStorage(this._dir);
  final Directory _dir;
  @override
  Future<Directory> root() async => _dir;
}

/// A roster shaped like the gym's: members joining across two years, billed
/// monthly on their joining day, most months paid in the first week and a
/// receipt for each, one in twelve deactivated along the way.
Future<void> _seed(File file, int members) async {
  final db = AppDatabase.forTesting(NativeDatabase(file));
  await seedDatabase(db);
  final admin = (await db.select(db.users).getSingle()).id;
  final plan = (await (db.select(db.membershipPlans)
            ..where((p) => p.name.equals('Monthly')))
          .getSingle());
  // Row by row through the duplicate-cycle trigger would take an hour at
  // 10,000 members; the rows themselves are ordinary. It is recreated on the
  // next open.
  await db.customStatement(
      'DROP TRIGGER IF EXISTS trg_periods_one_per_member_insert');

  var periodId = 0, paymentId = 0;
  const chunk = 500;
  for (var start = 1; start <= members; start += chunk) {
    await db.batch((b) {
      for (var i = start; i < start + chunk && i <= members; i++) {
        final monthsBack = i % 24;
        final day = 1 + i % 27;
        final joined = DateTime.utc(2026, 11 - monthsBack, day);
        final inactive = i % 12 == 0;
        final stopAfter = inactive ? monthsBack ~/ 2 : monthsBack;
        b.insert(
            db.members,
            MembersCompanion.insert(
              id: Value(i),
              memberCode: i,
              fullName: 'Test Member $i',
              phone: '+92300${(1000000 + i).toString()}',
              joiningDate: joined,
              deactivatedAt: Value(inactive
                  ? DateTime.utc(2026, 11 - monthsBack + stopAfter, day)
                  : null),
            ));
        b.insert(
            db.memberships,
            MembershipsCompanion.insert(
              id: Value(i),
              memberId: i,
              planId: plan.id,
              startDate: joined,
              billingAnchorDay: Value(day),
            ));
        for (var k = 0; k <= stopAfter; k++) {
          final cycleStart = DateTime.utc(2026, 11 - monthsBack + k, day);
          if (cycleStart.isAfter(_now.toUtc())) break;
          final current = k == monthsBack;
          final paid = current ? (i + k) % 5 < 3 : (i * 7 + k) % 10 != 0;
          final pid = ++periodId;
          final paidOn = DateTime(cycleStart.year, cycleStart.month,
              cycleStart.day + (i + k) % 6, 10);
          b.insert(
              db.membershipPeriods,
              MembershipPeriodsCompanion.insert(
                id: Value(pid),
                membershipId: i,
                periodStart: cycleStart,
                periodEnd: DateTime.utc(cycleStart.year, cycleStart.month + 1,
                    cycleStart.day),
                expectedAmountMinor: plan.priceMinor,
                settledAt: Value(paid && !paidOn.isAfter(_now)
                    ? paidOn.toUtc()
                    : null),
              ));
          if (!paid || paidOn.isAfter(_now)) continue;
          final pay = ++paymentId;
          b.insert(
              db.payments,
              PaymentsCompanion.insert(
                id: Value(pay),
                memberId: i,
                membershipPeriodId: Value(pid),
                amountMinor: plan.priceMinor,
                method: PaymentMethod.values[(i + k) % 4],
                paymentDate: paidOn,
                recordedById: admin,
                idempotencyKey: 'seed-$pay',
                source: Value(k + 12 < monthsBack
                    ? PaymentSource.imported
                    : PaymentSource.manual),
              ));
          b.insert(
              db.paymentAllocations,
              PaymentAllocationsCompanion.insert(
                  paymentId: pay, membershipPeriodId: pid,
                  amountMinor: plan.priceMinor));
          b.insert(
              db.receipts,
              ReceiptsCompanion.insert(
                receiptNumber: 'SEED-${pay.toString().padLeft(7, '0')}',
                paymentId: pay,
                pngPath: '',
              ));
        }
      }
    });
  }
  await db.close();
}

class _Result {
  _Result(this.size, this.name, this.medianMs, this.minMs, this.statements);
  final int size;
  final String name;
  final double medianMs;
  final double minMs;
  final int statements;

  Map<String, Object> toJson() => {
        'size': size,
        'op': name,
        'median_ms': medianMs,
        'min_ms': minMs,
        'statements': statements,
      };
}

void main() {
  final outDir = Directory(_out.isEmpty
      ? p.join(Directory.systemTemp.path, 'rmf-perf')
      : _out)
    ..createSync(recursive: true);
  final results = <_Result>[];

  for (final size in _sizes.split(',').map(int.parse)) {
    test('$size members', () async {
      final seedFile = File(p.join(outDir.path, 'seed_$size.sqlite'));
      if (!seedFile.existsSync()) {
        final sw = Stopwatch()..start();
        await _seed(seedFile, size);
        // ignore: avoid_print
        print('seeded $size members in ${sw.elapsed.inSeconds}s');
      }
      final work = File(p.join(outDir.path, 'work_${_label}_$size.sqlite'));
      seedFile.copySync(work.path);

      final counter = _Counter();
      // A background isolate, as the app's own connection is, so moving rows
      // across isolates is in the timings.
      AppDatabase open() => AppDatabase.forTesting(
          NativeDatabase.createInBackground(work).interceptWith(counter));

      Future<void> measure(String name, Future<void> Function() op,
          {int runs = 5, bool warm = true}) async {
        if (warm) await op();
        final times = <double>[];
        var statements = 0;
        for (var r = 0; r < runs; r++) {
          counter.statements = 0;
          final sw = Stopwatch()..start();
          await op();
          times.add(sw.elapsedMicroseconds / 1000);
          statements = counter.statements;
        }
        times.sort();
        results.add(_Result(
            size, name, times[times.length ~/ 2], times.first, statements));
        // ignore: avoid_print
        print('$size\t$name\t${times[times.length ~/ 2].toStringAsFixed(1)} ms'
            '\t$statements stmts');
      }

      // --- Opening the database: migrations, indexes, triggers, checks.
      await measure('open database', () async {
        final db = open();
        await db.customSelect('SELECT 1').get();
        await db.close();
      }, warm: false, runs: 3);

      final db = open();
      addTearDown(db.close);
      final members = MemberRepository(db);
      final payments = PaymentRepository(db);
      final receipts = ReceiptRepository(db);

      await measure('startup maintenance', () => runStartupMaintenance(db, now: _now),
          runs: 3);

      await measure('dashboard load', () async {
        final bloc = DashboardBloc(
          memberRepository: members,
          paymentRepository: payments,
          receiptRepository: receipts,
          clock: () => _now,
        );
        bloc.add(const DashboardRequested());
        await bloc.stream.firstWhere((s) => s.status != DashboardStatus.loading);
        await bloc.close();
      });

      await measure('sidebar due badge (filterCounts)',
          () => members.filterCounts(now: _now));

      await measure('members screen, all',
          () => members.listWithCounts(now: _now));
      await measure('members search "member 12"',
          () => members.listWithCounts(search: 'member 12', now: _now));
      await measure('members search "0300-100"',
          () => members.listWithCounts(search: '0300-100', now: _now));

      await measure('payments screen', () async {
        await payments.history();
        await payments.historyTotals();
      });
      await measure('payments search "member 12"', () async {
        await payments.history(search: 'member 12');
        await payments.historyTotals(search: 'member 12');
      });

      await measure('member profile', () async {
        await members.byId(size ~/ 2, now: _now);
        await payments.history(memberId: size ~/ 2);
      });

      final reminders = ReminderService(
          db: db, clientFactory: () async => MockWhatsAppClient());
      await measure('reminders queue', () => reminders.buildQueue(now: _now));

      final reports = ReportRepository(db, members: members, clock: () => _now);
      await measure('report, current month',
          () => reports.build(ReportMonth.of(_now)));
      await measure('report, a past month',
          () => reports.build(const ReportMonth(2026, 6)));

      // --- Writes: recording a payment end to end, less the receipt image.
      final workspace = await Directory.systemTemp.createTemp('rmf-perf');
      addTearDown(() => workspace.delete(recursive: true));
      final cycles = BillingCycleService(db);
      final record = RecordPaymentService(
        db: db,
        renderer: _FakeRenderer(),
        storage: _FakeStorage(workspace),
        clientFactory: () async => MockWhatsAppClient(),
        cycles: cycles,
      );
      final admin = (await db.select(db.users).getSingle()).id;
      var key = 0;
      // Members owing this month: every fifth has an unpaid current cycle.
      final owing = (await members.list(filter: MemberFilter.due, now: _now))
          .map((m) => m.id)
          .toList();
      await measure('record a payment', () async {
        await record.recordAdvancePayment(AdvancePaymentInput(
          memberId: owing[key % owing.length],
          amountMinor: 300000,
          method: PaymentMethod.cash,
          paymentDate: _now,
          sendWhatsApp: false,
          recordedById: admin,
          idempotencyKey: 'perf-$_label-${key++}',
        ));
      }, runs: 7);

      await measure('add a member', () async {
        final plan = (await db.select(db.membershipPlans).get()).first;
        await members.create(
          fullName: 'Perf Added ${key++}',
          phone: '+9233${(1000000 + key).toString()}',
          planId: plan.id,
          joiningDate: _now.toUtc(),
        );
      }, runs: 7);
    }, timeout: const Timeout(Duration(minutes: 30)));
  }

  tearDownAll(() {
    File(p.join(outDir.path, '$_label.json')).writeAsStringSync(
        const JsonEncoder.withIndent(' ')
            .convert([for (final r in results) r.toJson()]));
  });
}
